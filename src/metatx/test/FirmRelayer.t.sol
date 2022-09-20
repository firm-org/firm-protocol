// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";

import "../FirmRelayer.sol";

contract FirmRelayerTest is FirmTest {
    FirmRelayer relayer;

    function setUp() public {
        relayer = new FirmRelayer();
    }

    // For this test we need to fix both the address of FirmRelayer and chainId so that the hash
    // matches a hash generated off-chain with those parameters
    // Gen script: https://gist.github.com/izqui/f0379eb81c5e46f79696f88736ce1ffa
    function testGeneratesTypeHashCorrectly() public {
        // generate a deployer address so FirmRelayer is always deployed to the same address for this test
        address deployer = account("deployer"); // 0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946
        vm.setNonce(deployer, 1);
        vm.chainId(1000);
        vm.prank(deployer);
        relayer = new FirmRelayer();
        
        // Make sure FirmRelayer was deployed to the expected address
        assertEq(address(relayer), 0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264);

        FirmRelayer.RelayRequest memory request;
        request.from = deployer;
        request.nonce = 1000;

        FirmRelayer.Call memory call;
        call.to = address(relayer);
        call.value = 1;
        call.gas = 2;
        call.data = hex"12345678";
        call.assertionIndex = 1;

        FirmRelayer.Call[] memory calls = new FirmRelayer.Call[](2);
        calls[0] = call;
        calls[1] = call;

        request.calls = calls;

        // request has 2 calls and 0 assertions
        bytes32 typedDataHashA = relayer.requestTypedDataHash(request);

        FirmRelayer.Assertion memory assertion = FirmRelayer.Assertion(0, bytes32(uint256(1)));
        FirmRelayer.Assertion[] memory assertions = new FirmRelayer.Assertion[](3);
        assertions[0] = assertion;
        assertions[1] = assertion;
        assertions[2] = assertion;

        request.assertions = assertions;

        // request has the same 2 calls plus 3 assertions
        bytes32 typedDataHashB = relayer.requestTypedDataHash(request);

        assertEq(typedDataHashA, 0xd8c857d6367abed947ea9716c5f70eb68e350fec45d1e8cca0ec2b7de1b42a9e);
        assertEq(typedDataHashB, 0x51850391e64e0b4a7c15d6fd35c7a388a2c39b664d962b875d348a8117ce4116);
    }
}