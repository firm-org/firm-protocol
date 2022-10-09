// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../../test/BudgetModuleTest.sol";

import {LlamaPayFactory, LlamaPay} from "llamapay/LlamaPayFactory.sol";

import {LlamaPayStreams} from "../LlamaPayStreams.sol";

contract LlamaPayStreamsTest is BudgetModuleTest {
    LlamaPayFactory llamaPayFactory;

    LlamaPayStreams streams;
    uint256 allowanceId;

    constructor() {
        // Deployed just once to mimic how we deal with an existing instance
        llamaPayFactory = new LlamaPayFactory();
    }

    function setUp() public override {
        super.setUp();

        streams = LlamaPayStreams(createProxy(new LlamaPayStreams(llamaPayFactory), moduleInitData()));
        allowanceId = dailyAllowanceFor(address(streams), 1000 ether);
    }

    function testCreateStream() public returns (LlamaPay llamaPay) {
        vm.prank(address(avatar));
        streams.startStream(allowanceId);

        (llamaPay, ) = streams.streamManagers(allowanceId);
        assertEq(address(llamaPay.token()), address(token));
    }

    function testCreateStreamReusingInstance() public {
        LlamaPay llamaPay1 = testCreateStream();
        uint256 allowanceId2 = dailyAllowanceFor(address(streams), 1000 ether);

        vm.prank(address(avatar));
        streams.startStream(allowanceId2);
        
        (LlamaPay llamaPay2, ) = streams.streamManagers(allowanceId2);
        assertEq(address(llamaPay1), address(llamaPay2));
        assertEq(address(llamaPay2.token()), address(token));
    }

    function testCantCreateStreamIfNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(BudgetModule.UnauthorizedNotAllowanceAdmin.selector, allowanceId, address(this)));
        streams.startStream(allowanceId);
    }
}
