// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {LlamaPay, LlamaPayFactory} from "llamapay/LlamaPayFactory.sol";
import {IERC20, IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {BudgetModule} from "../BudgetModule.sol";
import {ForwarderLib} from "./ForwarderLib.sol";

contract LlamaPayStreams is BudgetModule {
    using ForwarderLib for ForwarderLib.Forwarder;

    string public constant moduleId = "org.firm.budget.llamapay-streams";
    uint256 public constant moduleVersion = 1;

    // See https://github.com/LlamaPay/llamapay/blob/90d18e11b94b02208100b3ac8756955b1b726d37/contracts/LlamaPay.sol#L16
    uint256 internal constant LLAMAPAY_DECIMALS = 20;
    LlamaPayFactory internal immutable llamaPayFactory;

    struct StreamConfig {
        bool enabled;
        IERC20 token;
        uint8 decimals;

        uint40 prepayBuffer;
    }

    mapping(uint256 => StreamConfig) public streamConfigs;

    error NoStreamsYet(uint256 allowanceId);
    error StreamsNotConfigured(uint256 allowanceId);
    error UnsupportedTokenDecimals();

    constructor(LlamaPayFactory llamaPayFactory_) {
        // NOTE: This immutable value is set in the constructor of the implementation contract
        // and all proxies will read from it as it gets saved in the bytecode
        llamaPayFactory = llamaPayFactory_;
    }

    function configure(uint256 allowanceId, uint40 prepayBuffer) external onlyAllowanceAdmin(allowanceId) {
        StreamConfig storage streamConfig = streamConfigs[allowanceId];

        if (!streamConfig.enabled) {
            _setupStreamForAllowance(streamConfig, allowanceId);
        }

        streamConfig.prepayBuffer = prepayBuffer;
    }

    // LlamaPay always uses numbers with 20 decimals
    function startStream(uint256 allowanceId, address to, uint256 amountPerSec, string calldata description)
        external
        onlyAllowanceAdmin(allowanceId)
    {
        StreamConfig storage streamConfig = _getStreamConfig(allowanceId);
        IERC20 token = streamConfig.token;
        LlamaPay streamer = _streamerForToken(token);
        ForwarderLib.Forwarder forwarder = ForwarderLib.getForwarder(_forwarderSalt(allowanceId, token));

        forwarder.forwardChecked(
            address(streamer), abi.encodeCall(streamer.createStreamWithReason, (to, uint216(amountPerSec), description))
        );
        deposit(allowanceId);
    }

    // Unprotected
    function deposit(uint256 allowanceId) public {
        StreamConfig storage streamConfig = _getStreamConfig(allowanceId);
        IERC20 token = streamConfig.token;
        LlamaPay streamer = _streamerForToken(token);
        ForwarderLib.Forwarder forwarder = ForwarderLib.getForwarder(_forwarderSalt(allowanceId, token));

        (uint40 lastUpdate, uint216 paidPerSec) = streamer.payers(forwarder.addr());

        if (lastUpdate == 0) {
            revert NoStreamsYet(allowanceId);
        }

        uint256 existingBalance = streamer.balances(forwarder.addr());
        uint256 secondsToFund = uint40(block.timestamp) + streamConfig.prepayBuffer - lastUpdate;
        uint256 amount = secondsToFund * paidPerSec - existingBalance;
        uint256 tokenAmount = amount / (10 ** (LLAMAPAY_DECIMALS - streamConfig.decimals));
        // The first time we do a deposit, we leave one token in the forwarder
        // as a gas optimization
        bool leaveExtraToken = existingBalance == 0 && token.balanceOf(forwarder.addr()) == 0;

        budget().executePayment(allowanceId, forwarder.addr(), tokenAmount + (leaveExtraToken ? 1 : 0), "Streams deposit");
        forwarder.forwardChecked(address(streamer), abi.encodeCall(streamer.deposit, (tokenAmount)));
    }

    function _getStreamConfig(uint256 allowanceId) internal view returns (StreamConfig storage streamConfig) {
        streamConfig = streamConfigs[allowanceId];

        if (!streamConfig.enabled) {
            revert StreamsNotConfigured(allowanceId);
        }
    }

    function _setupStreamForAllowance(StreamConfig storage streamConfig, uint256 allowanceId) internal {
        // The `onlyAllowanceAdmin` modifier already ensured that the allowance exists
        (,,, address token,,,,) = budget().allowances(allowanceId);

        uint8 decimals = IERC20Metadata(token).decimals();
        if (decimals > 20) {
            revert UnsupportedTokenDecimals();
        }

        streamConfig.enabled = true;
        streamConfig.token = IERC20(token);
        streamConfig.decimals = decimals;

        (address streamer_, bool isDeployed) = llamaPayFactory.getLlamaPayContractByToken(token);
        if (!isDeployed) {
            llamaPayFactory.createLlamaPayContract(token);
        }
        ForwarderLib.Forwarder forwarder = ForwarderLib.create(_forwarderSalt(allowanceId, IERC20(token)));
        forwarder.forwardChecked(
            address(token), abi.encodeCall(IERC20.approve, (streamer_, type(uint256).max))
        );
    }

    function _streamerForToken(IERC20 token) internal view returns (LlamaPay) {
        (address streamer,) = llamaPayFactory.getLlamaPayContractByToken(address(token));
        return LlamaPay(streamer);
    }

    function _forwarderSalt(uint256 allowanceId, IERC20 token) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(allowanceId, token));
    }
}
