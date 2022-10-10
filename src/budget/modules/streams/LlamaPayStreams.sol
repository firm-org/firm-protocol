// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {LlamaPay, LlamaPayFactory} from "llamapay/LlamaPayFactory.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {BudgetModule} from "../BudgetModule.sol";
import {ForwarderLib} from "./ForwarderLib.sol";

contract LlamaPayStreams is BudgetModule {
    using ForwarderLib for ForwarderLib.Forwarder;

    string public constant moduleId = "org.firm.budget.llamapay-streams";
    uint256 public constant moduleVersion = 1;
    LlamaPayFactory internal immutable llamaPayFactory;

    struct StreamManager {
        LlamaPay streamer;
        ForwarderLib.Forwarder forwarder;
        uint40 prepayBuffer;
    }

    mapping(uint256 => StreamManager) public streamManagers;

    error NoStreamsYet(uint256 allowanceId);
    error StreamsNotConfigured(uint256 allowanceId);

    constructor(LlamaPayFactory llamaPayFactory_) {
        // NOTE: This immutable value is set in the constructor of the implementation contract
        // and all proxies will read from it as it gets saved in the bytecode
        llamaPayFactory = llamaPayFactory_;
    }

    function configure(uint256 allowanceId, uint40 prepayBuffer) external onlyAllowanceAdmin(allowanceId) {
        StreamManager storage streamManager = streamManagers[allowanceId];

        if (address(streamManager.streamer) == address(0)) {
            _setupStreamForAllowance(streamManager, allowanceId);
        }

        streamManager.prepayBuffer = prepayBuffer;
    }

    function startStream(uint256 allowanceId, address to, uint256 amountPerSec, string calldata description)
        external
        onlyAllowanceAdmin(allowanceId)
    {
        StreamManager storage streamManager = _getStreamManager(allowanceId);
        LlamaPay streamer = streamManager.streamer;
        ForwarderLib.Forwarder forwarder = streamManager.forwarder;

        forwarder.forwardChecked(
            address(streamer), abi.encodeCall(streamer.createStreamWithReason, (to, uint216(amountPerSec), description))
        );
        deposit(allowanceId);
    }
    
    // Unprotected
    function deposit(uint256 allowanceId) public {
        StreamManager storage streamManager = _getStreamManager(allowanceId);
        LlamaPay streamer = streamManager.streamer;
        ForwarderLib.Forwarder forwarder = streamManager.forwarder;

        (uint40 lastUpdate, uint216 paidPerSec) = streamer.payers(forwarder.addr());

        if (lastUpdate == 0) {
            revert NoStreamsYet(allowanceId);
        }

        uint256 secondsToFund = uint40(block.timestamp) + streamManager.prepayBuffer - lastUpdate;
        uint256 amount = secondsToFund * paidPerSec - streamer.balances(forwarder.addr());
        uint256 tokenAmount = amount / streamer.DECIMALS_DIVISOR();

        budget.executePayment(allowanceId, forwarder.addr(), tokenAmount, "Streams deposit");
        forwarder.forwardChecked(
            address(streamer), abi.encodeCall(streamer.deposit, (tokenAmount))
        );
    }

    function _getStreamManager(uint256 allowanceId) internal view returns (StreamManager storage) {
        StreamManager storage streamManager = streamManagers[allowanceId];

        if (address(streamManager.streamer) == address(0)) {
            revert StreamsNotConfigured(allowanceId);
        }

        return streamManager;
    }

    function _setupStreamForAllowance(StreamManager storage streamManager, uint256 allowanceId)
        internal
        returns (LlamaPay streamer)
    {
        // The `onlyAllowanceAdmin` modifier already ensured that the allowance exists
        (,,, address token,,,,) = budget.allowances(allowanceId);
        (address streamer_, bool isDeployed) = llamaPayFactory.getLlamaPayContractByToken(token);

        streamManager.forwarder = ForwarderLib.create(keccak256(abi.encodePacked(allowanceId, token)));
        streamManager.streamer = streamer = LlamaPay(streamer_);

        if (!isDeployed) {
            assert(streamer_ == llamaPayFactory.createLlamaPayContract(token));
        }

        streamManager.forwarder.forwardChecked(
            address(token), abi.encodeCall(IERC20.approve, (streamer_, type(uint256).max))
        );
    }
}
