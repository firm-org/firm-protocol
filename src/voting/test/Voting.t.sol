// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {DoubleEndedQueue} from "openzeppelin/utils/structs/DoubleEndedQueue.sol";

import {BaseCaptableTest, EquityToken, NO_CONVERSION_FLAG} from "../../captable/test/Captable.t.sol";
import {TargetV1 as Target} from "../../factory/test/lib/TestTargets.sol";
import {FirmRelayer} from "../../metatx/FirmRelayer.sol";
import {SafeAware} from "../../bases/SafeAware.sol";

import {Voting, SafeModule} from "../Voting.sol";

contract VotingTest is BaseCaptableTest {
    Voting voting;
    Target target;
    FirmRelayer relayer;

    uint256 constant QUORUM_NUMERATOR = 5000; // 50%
    uint256 constant VOTING_DELAY = 1;
    uint256 constant VOTING_PERIOD = 10;
    uint256 constant PROPOSAL_THRESHOLD = 1;

    uint256 constant INITIAL_AUTHORIZED = 10000;

    function setUp() public virtual override {
        vm.roll(1);

        super.setUp();

        target = new Target();
        relayer = new FirmRelayer();
        voting = Voting(
            payable(
                createProxy(
                    new Voting(),
                    abi.encodeCall(
                        Voting.initialize,
                        (
                            safe,
                            captable,
                            QUORUM_NUMERATOR,
                            VOTING_DELAY,
                            VOTING_PERIOD,
                            PROPOSAL_THRESHOLD,
                            address(relayer)
                        )
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
        _selfDelegateHolders(token);
        blocktravel(1);
    }

    function testInitialState() public {
        assertEq(voting.name(), "FirmVoting");
        assertEq(address(voting.token()), address(captable));
        assertEq(voting.quorumNumerator(), QUORUM_NUMERATOR);
        assertEq(voting.votingDelay(), VOTING_DELAY);
        assertEq(voting.votingPeriod(), VOTING_PERIOD);
        assertEq(voting.proposalThreshold(), PROPOSAL_THRESHOLD);
    }

    function testCantReinit() public {
        vm.expectRevert(abi.encodeWithSelector(SafeAware.AlreadyInitialized.selector));
        voting.initialize(
            safe, captable, QUORUM_NUMERATOR, VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD, address(relayer)
        );
    }

    function testCanCreateAndExecuteProposal() public {
        _createAndExecuteProposal(address(target), abi.encodeCall(target.setNumber, (1)), 0, 0);
        assertEq(target.getNumber(), 1);
    }

    function testCanCreateAndExecuteProposalWithValue() public {
        vm.deal(address(safe), 1);
        _createAndExecuteProposal(HOLDER1, 1, bytes(""), 0, 0);
        assertEq(HOLDER1.balance, 1);
    }

    function _createAndExecuteProposal(address to, bytes memory data, uint256 extraDelay, uint256 extraPeriod)
        internal
    {
        _createAndExecuteProposal(to, 0, data, extraDelay, extraPeriod);
    }

    function _createAndExecuteProposal(
        address to,
        uint256 value,
        bytes memory data,
        uint256 extraDelay,
        uint256 extraPeriod
    ) internal {
        blocktravel(1);
        vm.prank(HOLDER1);
        string memory description = "Test";
        uint256 proposalId = voting.propose(arr(address(to)), arr(value), arr(data), description);

        blocktravel(VOTING_DELAY + 1 + extraDelay);

        vm.prank(HOLDER1);
        voting.castVote(proposalId, 1);
        vm.prank(HOLDER2);
        voting.castVote(proposalId, 0);

        blocktravel(VOTING_PERIOD + extraPeriod);

        voting.execute(arr(address(to)), arr(value), arr(data), keccak256(bytes(description)));
    }

    function testProposalExecutionRevertsIfActionReverts() public {
        blocktravel(1);
        vm.prank(HOLDER1);
        string memory description = "Test";
        // Target has no fallback, so this will revert
        uint256 proposalId = voting.propose(arr(address(target)), arr(0), arr(bytes("")), description);

        blocktravel(VOTING_DELAY + 1);

        vm.prank(HOLDER1);
        voting.castVote(proposalId, 1);
        vm.prank(HOLDER2);
        voting.castVote(proposalId, 0);

        blocktravel(VOTING_PERIOD);

        vm.expectRevert(abi.encodeWithSelector(Voting.ProposalExecutionFailed.selector, proposalId));
        voting.execute(arr(address(target)), arr(0), arr(bytes("")), keccak256(bytes(description)));
    }

    function testCantCallSafeCallbackDirectly() public {
        vm.expectRevert(abi.encodeWithSelector(SafeModule.BadExecutionContext.selector));
        voting.__safeContext_execute(1, arr(address(0)), arr(0), arr(bytes("")), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(SafeModule.BadExecutionContext.selector));
        Voting votingImpl = Voting(payable(getImpl(address(voting))));
        votingImpl.__safeContext_execute(1, arr(address(0)), arr(0), arr(bytes("")), bytes32(0));
    }

    function testCanUpdateSettingsThroughProposals() public {
        _createAndExecuteProposal(
            address(voting), abi.encodeCall(voting.setProposalThreshold, (PROPOSAL_THRESHOLD + 1)), 0, 0
        );
        assertEq(voting.proposalThreshold(), PROPOSAL_THRESHOLD + 1);

        _createAndExecuteProposal(address(voting), abi.encodeCall(voting.setVotingDelay, (VOTING_DELAY + 1)), 0, 0);
        assertEq(voting.votingDelay(), VOTING_DELAY + 1);

        _createAndExecuteProposal(address(voting), abi.encodeCall(voting.setVotingPeriod, (VOTING_PERIOD + 1)), 1, 0);
        assertEq(voting.votingPeriod(), VOTING_PERIOD + 1);

        _createAndExecuteProposal(
            address(voting), abi.encodeCall(voting.updateQuorumNumerator, (QUORUM_NUMERATOR + 1)), 1, 1
        );
        assertEq(voting.quorumNumerator(), QUORUM_NUMERATOR + 1);
    }

    function testSafeCantUpdateSettingsDirectly() public {
        vm.startPrank(address(safe));

        vm.expectRevert(abi.encodeWithSelector(DoubleEndedQueue.Empty.selector));
        voting.setProposalThreshold(PROPOSAL_THRESHOLD + 1);

        vm.expectRevert(abi.encodeWithSelector(DoubleEndedQueue.Empty.selector));
        voting.setVotingDelay(VOTING_DELAY + 1);

        vm.expectRevert(abi.encodeWithSelector(DoubleEndedQueue.Empty.selector));
        voting.setVotingPeriod(VOTING_PERIOD + 1);

        vm.expectRevert(abi.encodeWithSelector(DoubleEndedQueue.Empty.selector));
        voting.updateQuorumNumerator(QUORUM_NUMERATOR + 1);

        vm.stopPrank();
    }

    function testVotingCantUpdateSettings() public {
        vm.startPrank(address(voting));

        vm.expectRevert("Governor: onlyGovernance");
        voting.setProposalThreshold(PROPOSAL_THRESHOLD + 1);

        vm.expectRevert("Governor: onlyGovernance");
        voting.setVotingDelay(VOTING_DELAY + 1);

        vm.expectRevert("Governor: onlyGovernance");
        voting.setVotingPeriod(VOTING_PERIOD + 1);

        vm.expectRevert("Governor: onlyGovernance");
        voting.updateQuorumNumerator(QUORUM_NUMERATOR + 1);

        vm.stopPrank();
    }

    function testFirmContextUsedInVoting() public {
        // Ensure that ERC2771 context from Firm is used and it's compatible with FirmRelayer
        FirmRelayer.Call[] memory calls = new FirmRelayer.Call[](1);
        calls[0] = FirmRelayer.Call({
            to: address(voting),
            value: 0,
            data: abi.encodeCall(voting.propose, (new address[](1), new uint256[](1), new bytes[](1), "Test")),
            assertionIndex: 0,
            gas: 1e6
        });
        uint256 proposalId = voting.hashProposal(new address[](1), new uint256[](1), new bytes[](1), keccak256(bytes("Test")));

        address nonShareholder = account("Non Shareholder");

        vm.prank(address(nonShareholder));
        bytes memory votingError = abi.encodeWithSignature("Error(string)", "Governor: proposer votes below proposal threshold");
        vm.expectRevert(
            abi.encodeWithSelector(FirmRelayer.CallExecutionFailed.selector, 0, address(voting), votingError)
        );
        relayer.selfRelay(calls, new FirmRelayer.Assertion[](0));

        vm.expectRevert("Governor: unknown proposal id");
        voting.state(proposalId);

        vm.prank(HOLDER1);
        relayer.selfRelay(calls, new FirmRelayer.Assertion[](0));
        assertEq(uint8(voting.state(proposalId)), 0);
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
