// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../../test/BudgetModuleTest.sol";

import {LlamaPayFactory, LlamaPay} from "llamapay/LlamaPayFactory.sol";

import {LlamaPayStreams, ForwarderLib} from "../LlamaPayStreams.sol";

contract LlamaPayStreamsTest is BudgetModuleTest {
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

    function testCreateStream() public returns (LlamaPay llamaPay, address payer, uint256 amountPerSec) {
        amountPerSec = basicMonthlyAmountToSecs(1000);

        vm.prank(address(avatar));
        streams.configure(allowanceId, 60 days);
        vm.prank(address(avatar));
        streams.startStream(allowanceId, RECEIVER, amountPerSec, "");

        timetravel(30 days);

        ForwarderLib.Forwarder payer_;
        (llamaPay, payer_,) = streams.streamManagers(allowanceId);
        payer = ForwarderLib.Forwarder.unwrap(payer_);
        assertEq(address(llamaPay.token()), address(token));

        llamaPay.withdraw(payer, RECEIVER, uint216(amountPerSec));
        assertBalance(RECEIVER, 1000, 1);
        assertBalance(address(llamaPay), 1000, 1);
    }

    function testCreateMultipleStreams() public {
        (LlamaPay llamaPay, address payer, uint256 amountPerSec1) = testCreateStream();

        uint256 amountPerSec2 = basicMonthlyAmountToSecs(2000);

        vm.prank(address(avatar));
        streams.startStream(allowanceId, RECEIVER, amountPerSec2, "");

        timetravel(30 days);

        llamaPay.withdraw(payer, RECEIVER, uint216(amountPerSec1));
        llamaPay.withdraw(payer, RECEIVER, uint216(amountPerSec2));
        assertBalance(RECEIVER, 4000, 3);
        assertBalance(address(llamaPay), 3000, 3);
    }

    function testCantCreateStreamIfNotAdmin() public {
        vm.prank(address(avatar));
        streams.configure(allowanceId, 1);
        vm.expectRevert(
            abi.encodeWithSelector(BudgetModule.UnauthorizedNotAllowanceAdmin.selector, allowanceId, address(this))
        );
        streams.startStream(allowanceId, RECEIVER, 1, "");
    }

    function assertBalance(address who, uint256 expectedBalance, uint256 maxDelta) internal {
        assertApproxEqAbs(token.balanceOf(who), expectedBalance * 10 ** token.decimals(), maxDelta);
    }

    function basicMonthlyAmountToSecs(uint256 monthlyAmount) internal pure returns (uint256) {
        return monthlyAmount * 10 ** 20 / (30 days);
    }
}
