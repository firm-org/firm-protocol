// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {LlamaPay, LlamaPayFactory} from "llamapay/LlamaPayFactory.sol";

import {BudgetModule} from "../BudgetModule.sol";

// TODO: implement in assembly using etk
contract OwnedForwarder {
    address internal immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    fallback() external payable {
        require(msg.data.length >= 20);

        address to = address(bytes20(msg.data[0:20]));
        bytes memory data = msg.data[20:];
        (bool ok, bytes memory ret) = to.call(data);

        if (ok) {
            assembly {
                return(add(ret, 0x20), mload(ret))
            }
        } else {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }
}

library ForwarderLib {
    type Forwarder is address;

    function create(bytes32 salt) internal returns (Forwarder) {
        return Forwarder.wrap(address(new OwnedForwarder{salt: salt}(address(this))));
    }

    function forward(Forwarder forwarder, address to, bytes memory data) internal returns (bool ok, bytes memory ret) {

    }
}

contract LlamaPayStreams is BudgetModule {
    using ForwarderLib for ForwarderLib.Forwarder;

    string public constant moduleId = "org.firm.budget.llamapay-streams";
    uint256 public constant moduleVersion = 1;
    LlamaPayFactory internal immutable llamaPayFactory;

    struct StreamManager {
        LlamaPay streamer;
        ForwarderLib.Forwarder forwarder;
    }

    mapping (uint256 => StreamManager) public streamManagers;

    constructor(LlamaPayFactory llamaPayFactory_) {
        // NOTE: This immutable value is set in the constructor of the implementation contract
        // and all proxies will read from it as it gets saved in the bytecode
        llamaPayFactory = llamaPayFactory_;
    }

    function startStream(uint256 allowanceId) external onlyAllowanceAdmin(allowanceId) {
        StreamManager storage streamManager = streamManagers[allowanceId];
        LlamaPay streamer = streamManager.streamer;

        if (address(streamer) == address(0)) {
            streamer = _setupStreamForAllowance(streamManager, allowanceId);
        }
    }

    function _setupStreamForAllowance(StreamManager storage streamManager, uint256 allowanceId) internal returns (LlamaPay streamer) {
        // The `onlyAllowanceAdmin` modifier already ensured that the allowance exists
        (,,, address token,,,,) = budget.allowances(allowanceId);
        (address streamer_, bool isDeployed) = llamaPayFactory.getLlamaPayContractByToken(token);

        streamManager.forwarder = ForwarderLib.create(keccak256(abi.encodePacked(allowanceId, token)));
        streamManager.streamer = streamer = LlamaPay(streamer_);

        if (!isDeployed) {
            assert(streamer_ == llamaPayFactory.createLlamaPayContract(token));
        }
    }
}
