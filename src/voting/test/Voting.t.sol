// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseCaptableTest, EquityToken, NO_CONVERSION_FLAG} from "../../captable/test/Captable.t.sol";
import {TargetV1 as Target} from "../../factory/test/lib/TestTargets.sol";

import {Voting} from "../Voting.sol";

contract BaseVotingTest is BaseCaptableTest {
    Voting voting;
    Target target;

    uint256 constant QUORUM_NUMERATOR = 5000; // 50%
    uint256 constant VOTING_DELAY = 1;
    uint256 constant VOTING_PERIOD = 10;
    uint256 constant PROPOSAL_THRESHOLD = 1;

    uint256 constant INITIAL_AUTHORIZED = 10000;

    function setUp() public virtual override {
        super.setUp();

        target = new Target();
        voting = Voting(
            payable(
                createProxy(
                    new Voting(),
                    abi.encodeCall(
                        Voting.initialize,
                        (safe, captable, QUORUM_NUMERATOR, VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD, address(0))
                    )
                )
            )
        );

        vm.startPrank(address(safe));
        (uint256 classId, EquityToken token) =
            captable.createClass("Common", "TST-A", INITIAL_AUTHORIZED, NO_CONVERSION_FLAG, 1, ALLOW_ALL_BOUNCER);
        captable.setManager(classId, ISSUER, true);
        vm.stopPrank();
        vm.startPrank(ISSUER);
        captable.issue(HOLDER1, classId, INITIAL_AUTHORIZED / 2 + 1);
        captable.issue(HOLDER2, classId, INITIAL_AUTHORIZED / 2 - 1);
        vm.stopPrank();
        blocktravel(1);
        _selfDelegateHolders(token);
    }

    function testCanCreateProposal() public {
        blocktravel(1);
        vm.prank(HOLDER1);
        string memory description = "Test";
        uint256 proposalId = voting.propose(arr(address(target)), arr(0), arr(abi.encodeCall(target.setNumber, (1))), description);

        blocktravel(VOTING_DELAY + 1);

        vm.prank(HOLDER1);
        voting.castVote(proposalId, 1);
        vm.prank(HOLDER2);
        voting.castVote(proposalId, 0);

        blocktravel(VOTING_PERIOD);

        voting.execute(arr(address(target)), arr(0), arr(abi.encodeCall(target.setNumber, (1))), keccak256(bytes(description)));

        assertEq(target.getNumber(), 1);
    }

    function arr(address a) internal pure returns (address[] memory _arr) {
        _arr = new address[](1);
        _arr[0] = a;
    }

    function arr(bytes memory a) internal pure returns (bytes[] memory _arr) {
        _arr = new bytes[](1);
        _arr[0] = a;
    }

    function arr(uint256 a) internal pure returns (uint256[] memory _arr) {
        _arr = new uint256[](1);
        _arr[0] = a;
    }
}
