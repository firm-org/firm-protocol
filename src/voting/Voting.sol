// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {OZGovernor, Context} from "./OZGovernor.sol";
import {ICaptableVotes} from "../captable/interfaces/ICaptableVotes.sol";

import {FirmBase, ISafe, ERC2771Context, IMPL_INIT_NOOP_ADDR, IMPL_INIT_NOOP_SAFE} from "../bases/FirmBase.sol";
import {SafeModule} from "../bases/SafeModule.sol";

/**
 * @title Voting
 * @author Firm (engineering@firm.org)
 * @notice Voting module wrapping OpenZeppelin's Governor compatible with Firm's Captable
 * https://docs.openzeppelin.com/contracts/4.x/api/governance
 */
contract Voting is FirmBase, SafeModule, OZGovernor {
    string public constant moduleId = "org.firm.voting";
    uint256 public constant moduleVersion = 1;

    error ProposalExecutionFailed(uint256 proposalId);

    constructor() {
        // Initialize with impossible values in constructor so impl base cannot be used
        initialize(
            IMPL_INIT_NOOP_SAFE, ICaptableVotes(IMPL_INIT_NOOP_ADDR), quorumDenominator(), 0, 1, 1, IMPL_INIT_NOOP_ADDR
        );
    }

    function initialize(
        ISafe safe_,
        ICaptableVotes token_,
        uint256 quorumNumerator_,
        uint256 votingDelay_,
        uint256 votingPeriod_,
        uint256 proposalThreshold_,
        address trustedForwarder_
    ) public {
        // calls SafeAware.__init_setSafe which reverts on reinitialization
        __init_firmBase(safe_, trustedForwarder_);
        _setupGovernor(token_, quorumNumerator_, votingDelay_, votingPeriod_, proposalThreshold_);
    }

    function _executor() internal view override returns (address) {
        return address(safe());
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override {
        bytes memory data =
            abi.encodeCall(this.__safeContext_execute, (proposalId, targets, values, calldatas, descriptionHash));

        if (!_moduleExecDelegateCallToSelf(data)) {
            revert ProposalExecutionFailed(proposalId);
        }
    }

    function __safeContext_execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external onlyForeignContext {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    // Since both OZGovernor and FirmBase use ERC-2771 contexts but use different implementations
    // we need to override the following functions to specify to use FirmBase's implementation

    function _msgSender() internal view override(Context, ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }

    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }
}
