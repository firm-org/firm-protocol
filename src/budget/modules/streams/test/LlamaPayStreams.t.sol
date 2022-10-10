// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../../test/BudgetModuleTest.sol";

import {LlamaPayFactory, LlamaPay} from "llamapay/LlamaPayFactory.sol";

import {LlamaPayStreams, ForwarderLib} from "../LlamaPayStreams.sol";

contract LlamaPayStreamsTest is BudgetModuleTest {
    LlamaPayFactory llamaPayFactory;

    LlamaPayStreams streams;
    uint256 allowanceId;

    address RECEIVER = account("receiver");

    constructor() {
        // Deployed just once to mimic how we deal with an existing instance
        llamaPayFactory = new LlamaPayFactory();
    }

    function setUp() public override {
        super.setUp();

        streams = LlamaPayStreams(createProxy(new LlamaPayStreams(llamaPayFactory), moduleInitData()));
        allowanceId = dailyAllowanceFor(address(streams), 50000 ether);
    }

    function basicMonthlyAmountToSecs(uint256 monthlyAmount) internal returns (uint256) {
        return monthlyAmount * 10**20 / (30 days);
    }

    function testCreateStream() public returns (LlamaPay llamaPay) {
        uint256 amountPerSec = basicMonthlyAmountToSecs(1000);
        
        vm.warp(1);
        vm.prank(address(avatar));
        streams.configure(allowanceId, 8 weeks);
        vm.prank(address(avatar));
        streams.startStream(allowanceId, RECEIVER, amountPerSec, "");
        
        vm.warp(4 weeks);
        ForwarderLib.Forwarder payer;
        (llamaPay, payer,) = streams.streamManagers(allowanceId);
        assertEq(address(llamaPay.token()), address(token));

        llamaPay.withdraw(ForwarderLib.Forwarder.unwrap(payer), RECEIVER, uint216(amountPerSec));
    }

    /*
    function testCreateTwoStreamReusingInstance() public {
        LlamaPay llamaPay1 = testCreateStream();
        uint256 allowanceId2 = dailyAllowanceFor(address(streams), 1000 ether);

        vm.prank(address(avatar));
        streams.startStream(allowanceId2, RECEIVER, 1, "");

        (LlamaPay llamaPay2,,) = streams.streamManagers(allowanceId2);
        assertEq(address(llamaPay1), address(llamaPay2));
        assertEq(address(llamaPay2.token()), address(token));
    }
    */

    function testCantCreateStreamIfNotAdmin() public {
        vm.prank(address(avatar));
        streams.configure(allowanceId, 1);
        vm.expectRevert(
            abi.encodeWithSelector(BudgetModule.UnauthorizedNotAllowanceAdmin.selector, allowanceId, address(this))
        );
        streams.startStream(allowanceId, RECEIVER, 1, "");
    }
}
