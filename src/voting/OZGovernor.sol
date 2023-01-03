// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {Governor, IGovernor, Context} from "openzeppelin/governance/Governor.sol";
import {GovernorSettings} from "openzeppelin/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "openzeppelin/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotesQuorumFraction} from "openzeppelin/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorVotes, IVotes} from "openzeppelin/governance/extensions/GovernorVotes.sol";

contract OZGovernor is Governor, GovernorSettings, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction {
    constructor(IVotes captableVotes)
        Governor("FirmVoting")
        GovernorSettings(1 /* 1 block */, 50400 /* 1 week */, 0)
        GovernorVotes(captableVotes)
        GovernorVotesQuorumFraction(4)
    {}

    // Reject receiving assets

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        // Reject receiving assets
        return bytes4(0);
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155Received}.
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        // Reject receiving assets
        return bytes4(0);
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155BatchReceived}.
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        // Reject receiving assets
        return bytes4(0);
    }

    // The following functions are overrides required by Solidity.

    function votingDelay()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber)
        public
        view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }
}