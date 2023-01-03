// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {OZGovernor, IVotes, Context} from "./OZGovernor.sol";
import {ICaptableVotes} from "../captable/utils/ICaptableVotes.sol";

import {FirmBase, ERC2771Context} from "../bases/FirmBase.sol";
import {SafeModule} from "../bases/SafeModule.sol";

contract FirmVoting is FirmBase, SafeModule, OZGovernor {
    string public constant moduleId = "org.firm.voting";
    uint256 public constant moduleVersion = 1;

    error ProposalExecutionFailed(uint256 proposalId);
    
    // TODO: nuke it
    constructor() OZGovernor(IVotes(address(0))) {

    }

    // TODO: proper firm initialize

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override {
        bytes memory data = abi.encodeCall(
            this.__safeContext_execute, (
            proposalId,
            targets,
            values,
            calldatas,
            descriptionHash
        ));

        if (!_execDelegateCallToSelf(data)) {
            revert ProposalExecutionFailed(proposalId);
        }
    }

    function __safeContext_execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) onlyForeignContext external {
        _execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    // TODO: overrides
    // - name? only used for the domain separator, it is actually important to override it since it will be created on the fly
    // - getVotes which uses ICaptableVotes, drop GovernorVotes from the inheritance tree
    // - we need to edit GovernanceVotes to use a non-immutable ICaptableVotes
    // - QuorumChecker needs to use this contract + use 10000 for the quorum denominator

    function _executor() internal view override returns (address) {
        return address(safe());
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