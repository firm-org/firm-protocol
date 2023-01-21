// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../../test/BudgetModuleTest.sol";

import {LlamaPayFactory, LlamaPay} from "llamapay/LlamaPayFactory.sol";

import {LlamaPayStreams, ForwarderLib} from "../LlamaPayStreams.sol";

contract LlamaPayStreamsTest is BudgetModuleTest {
    using ForwarderLib for ForwarderLib.Forwarder;

    LlamaPayFactory llamaPayFactory;

    LlamaPayStreams streams;
    uint256 allowanceId;

    address RECEIVER = account("Receiver");

    constructor() {
        // Deployed just once to mimic how we deal with an existing instance
        llamaPayFactory = new LlamaPayFactory();
    }

    function setUp() public override {
        super.setUp();

        streams = LlamaPayStreams(createProxy(new LlamaPayStreams(llamaPayFactory), moduleInitData()));
        allowanceId = dailyAllowanceFor(address(streams), 50000 ether);
    }

    function module() internal view override returns (BudgetModule) {
        return streams;
    }

    function testCreateStream() public returns (LlamaPay llamaPay, address forwarder, uint256 amountPerSec) {
        amountPerSec = basicMonthlyAmountToSecs(1000);

        vm.prank(address(safe));
        streams.configure(allowanceId, 60 days);

        (bool enabled, IERC20 token_,,) = streams.streamConfigs(allowanceId);
        (address llamaPay_,) = llamaPayFactory.getLlamaPayContractByToken(address(token));
        llamaPay = LlamaPay(llamaPay_);
        forwarder = ForwarderLib.getForwarder(keccak256(abi.encodePacked(allowanceId, token)), address(streams)).addr();
        assertTrue(enabled);
        assertEq(address(llamaPay.token()), address(token));
        assertEq(address(token), address(token_));

        vm.prank(address(safe));
        streams.startStream(allowanceId, RECEIVER, amountPerSec, "");
        assertBalance(address(llamaPay), 2000, 1);
        assertOneLeftoverToken(forwarder);

        timetravel(30 days);

        llamaPay.withdraw(forwarder, RECEIVER, uint216(amountPerSec));
        assertBalance(RECEIVER, 1000, 1);
        assertBalance(address(llamaPay), 1000, 1);
    }

    function testCantCreateStreamIfNotAdmin() public {
        vm.prank(address(safe));
        streams.configure(allowanceId, 1);
        vm.expectRevert(
            abi.encodeWithSelector(BudgetModule.UnauthorizedNotAllowanceAdmin.selector, allowanceId, address(this))
        );
        streams.startStream(allowanceId, RECEIVER, 1, "");
    }

    function testCreateMultipleStreams() public {
        (LlamaPay llamaPay, address forwarder, uint256 amountPerSec1) = testCreateStream();

        uint256 amountPerSec2 = basicMonthlyAmountToSecs(2000);

        vm.prank(address(safe));
        streams.startStream(allowanceId, RECEIVER, amountPerSec2, "");
        assertOneLeftoverToken(forwarder);

        timetravel(30 days);

        llamaPay.withdraw(forwarder, RECEIVER, uint216(amountPerSec1));
        llamaPay.withdraw(forwarder, RECEIVER, uint216(amountPerSec2));
        assertBalance(RECEIVER, 4000, 3);
        assertBalance(address(llamaPay), 3000, 3);
    }

    function testCanChangePrepayBuffer() public {
        (LlamaPay llamaPay, address forwarder,) = testCreateStream();

        streams.rebalance(allowanceId);
        assertBalance(address(llamaPay), 2000, 1);
        assertOneLeftoverToken(forwarder);

        // Double it first
        vm.prank(address(safe));
        streams.setPrepayBuffer(allowanceId, 120 days);
        assertBalance(address(llamaPay), 4000, 1);
        assertOneLeftoverToken(forwarder);

        // Rebalance has no effect since setPrepayBuffer() already triggered a rebalance and time didn't pass
        streams.rebalance(allowanceId);
        assertBalance(address(llamaPay), 4000, 1);

        // Decrease it once triggering the first debit
        vm.prank(address(safe));
        streams.setPrepayBuffer(allowanceId, 30 days);
        assertBalance(address(llamaPay), 1000, 1);
        assertOneLeftoverToken(forwarder);

        // Decrease it again triggering another debit (wasn't approved again)
        vm.prank(address(safe));
        streams.setPrepayBuffer(allowanceId, 15 days);
        assertBalance(address(llamaPay), 500, 2);
        assertOneLeftoverToken(forwarder);
    }

    function testCanModifyStream() public {
        (LlamaPay llamaPay, address forwarder, uint256 amountPerSec) = testCreateStream();
        streams.rebalance(allowanceId);
        assertBalance(address(llamaPay), 2000, 1);
        assertOneLeftoverToken(forwarder);

        address newReceiver = account("New Receiver");
        uint256 newAmountPerSec = basicMonthlyAmountToSecs(2000);
        vm.prank(address(safe));
        streams.modifyStream(allowanceId, RECEIVER, amountPerSec, newReceiver, newAmountPerSec);
        assertBalance(address(llamaPay), 4000, 1);
        assertOneLeftoverToken(forwarder);

        timetravel(30 days);

        vm.expectRevert("stream doesn't exist");
        llamaPay.withdraw(forwarder, RECEIVER, uint216(amountPerSec));

        llamaPay.withdraw(forwarder, newReceiver, uint216(newAmountPerSec));
        assertBalance(newReceiver, 2000, 1);
        assertBalance(address(llamaPay), 2000, 1);
    }

    function testCantModifyStreamIfNotAdmin() public {
        (,, uint256 amountPerSec) = testCreateStream();
        vm.expectRevert(
            abi.encodeWithSelector(BudgetModule.UnauthorizedNotAllowanceAdmin.selector, allowanceId, address(this))
        );
        streams.modifyStream(allowanceId, RECEIVER, amountPerSec, account("someone"), 1);
    }

    function testCanPauseStream() public {
        (LlamaPay llamaPay, address forwarder, uint256 amountPerSec) = testCreateStream();

        vm.prank(address(safe));
        streams.pauseStream(allowanceId, RECEIVER, amountPerSec);

        assertBalance(address(llamaPay), 0, 1);

        vm.expectRevert("stream doesn't exist");
        llamaPay.withdraw(forwarder, RECEIVER, uint216(amountPerSec));
    }

    function testCantPauseStreamIfNotAdmin() public {
        (,, uint256 amountPerSec) = testCreateStream();
        vm.expectRevert(
            abi.encodeWithSelector(BudgetModule.UnauthorizedNotAllowanceAdmin.selector, allowanceId, address(this))
        );
        streams.pauseStream(allowanceId, RECEIVER, amountPerSec);
    }

    function testCanCancelStream() public {
        (LlamaPay llamaPay, address forwarder, uint256 amountPerSec) = testCreateStream();

        vm.prank(address(safe));
        streams.cancelStream(allowanceId, RECEIVER, amountPerSec);

        assertBalance(address(llamaPay), 0, 1);

        vm.expectRevert("stream doesn't exist");
        llamaPay.withdraw(forwarder, RECEIVER, uint216(amountPerSec));
    }

    function testCantCancelStreamIfNotAdmin() public {
        (,, uint256 amountPerSec) = testCreateStream();
        vm.expectRevert(
            abi.encodeWithSelector(BudgetModule.UnauthorizedNotAllowanceAdmin.selector, allowanceId, address(this))
        );
        streams.cancelStream(allowanceId, RECEIVER, amountPerSec);
    }

    function testCantSetPrepayBufferToZero() public {
        testCreateStream();
        vm.expectRevert(abi.encodeWithSelector(LlamaPayStreams.InvalidPrepayBuffer.selector, allowanceId));
        vm.prank(address(safe));
        streams.setPrepayBuffer(allowanceId, 0);
    }

    function testCantRebalanceIfNoStreamsHaveBeenCreated() public {
        vm.prank(address(safe));
        streams.configure(allowanceId, 60 days);
        vm.expectRevert(abi.encodeWithSelector(LlamaPayStreams.NoStreamsToRebalance.selector, allowanceId));
        streams.rebalance(allowanceId);
    }

    function testCantRebalanceIfStreamsHaventBeenConfigured() public {
        vm.expectRevert(abi.encodeWithSelector(LlamaPayStreams.StreamsNotConfigured.selector, allowanceId));
        streams.rebalance(allowanceId);
    }

    function testCantConfigureStreamsAgain() public {
        testCreateStream();
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(LlamaPayStreams.StreamsAlreadyConfigured.selector, allowanceId));
        streams.configure(allowanceId, 60 days);
    }

    function assertBalance(address who, uint256 expectedBalance, uint256 maxDelta) internal {
        assertApproxEqAbs(token.balanceOf(who), expectedBalance * 10 ** token.decimals(), maxDelta);
    }

    function assertOneLeftoverToken(address forwarder) internal {
        assertEq(token.balanceOf(forwarder), 1);
    }

    function basicMonthlyAmountToSecs(uint256 monthlyAmount) internal pure returns (uint256) {
        return monthlyAmount * 10 ** 20 / (30 days);
    }
}
