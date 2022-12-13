// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";

import "../FirmRelayer.sol";
import "./mocks/RelayTarget.sol";

contract FirmRelayerTest is FirmTest {
    FirmRelayer relayer;
    RelayTarget target;

    address immutable USER;
    uint256 immutable USER_PK;

    constructor() {
        (USER, USER_PK) = accountAndKey("user");
    }

    function setUp() public {
        relayer = new FirmRelayer();
        target = new RelayTarget(address(relayer));
    }

    function testBasicRelay() public {
        FirmRelayer.Call memory call = _defaultCallWithData(address(target), abi.encodeCall(target.onlySender, (USER)));
        FirmRelayer.RelayRequest memory request = _defaultRequestWithCall(call);

        relayer.relay(request, _signPacked(relayer.requestTypedDataHash(request), USER_PK));

        assertEq(target.lastSender(), USER);
        assertEq(relayer.getNonce(USER), 1);
    }

    function testRelayWithAssertion() public {
        FirmRelayer.Call memory call = _defaultCallWithData(address(target), abi.encodeCall(target.onlySender, (USER)));
        FirmRelayer.Assertion memory assertion = FirmRelayer.Assertion(0, bytes32(abi.encode(USER)));
        FirmRelayer.RelayRequest memory request = _defaultRequestWithCallAndAssertion(call, assertion);

        relayer.relay(request, _signPacked(relayer.requestTypedDataHash(request), USER_PK));

        assertEq(target.lastSender(), USER);
        assertEq(relayer.getNonce(USER), 1);
    }

    function testRelayNonceIncreases() public {
        testBasicRelay();

        FirmRelayer.Call memory call = _defaultCallWithData(address(target), abi.encodeCall(target.onlySender, (USER)));
        FirmRelayer.RelayRequest memory request = _defaultRequestWithCall(call);
        assertEq(request.nonce, 1);

        relayer.relay(request, _signPacked(relayer.requestTypedDataHash(request), USER_PK));

        assertEq(target.lastSender(), USER);
        assertEq(relayer.getNonce(USER), 2);
    }

    function testRevertOnForgedSignature() public {
        (, uint256 otherUserPk) = accountAndKey("other user");

        FirmRelayer.Call memory call = _defaultCallWithData(address(target), abi.encodeCall(target.onlySender, (USER)));
        FirmRelayer.RelayRequest memory request = _defaultRequestWithCall(call);
        bytes32 hash = relayer.requestTypedDataHash(request);

        vm.expectRevert(abi.encodeWithSelector(FirmRelayer.BadSignature.selector));
        relayer.relay(request, _signPacked(hash, otherUserPk));
    }

    function testRevertOnInvalidSignature() public {
        FirmRelayer.Call memory call = _defaultCallWithData(address(target), abi.encodeCall(target.onlySender, (USER)));
        FirmRelayer.RelayRequest memory request = _defaultRequestWithCall(call);

        bytes memory signature = _signPacked(relayer.requestTypedDataHash(request), USER_PK);
        assembly {
            // randomly change one byte from the signature
            let p := add(signature, 33)
            mstore8(p, add(1, byte(0, mload(p))))
        }
        vm.expectRevert(abi.encodeWithSelector(FirmRelayer.BadSignature.selector));
        relayer.relay(request, signature);
    }

    function testRevertOnRepeatedNonce() public {
        testBasicRelay();

        FirmRelayer.Call memory call = _defaultCallWithData(address(target), abi.encodeCall(target.onlySender, (USER)));
        FirmRelayer.RelayRequest memory request = _defaultRequestWithCall(call);
        request.nonce = 0;

        bytes32 hash = relayer.requestTypedDataHash(request);
        vm.expectRevert(abi.encodeWithSelector(FirmRelayer.BadNonce.selector, 1));
        relayer.relay(request, _signPacked(hash, USER_PK));
    }

    function testRevertOnTargetBadSender() public {
        (address otherUser, uint256 otherUserPk) = accountAndKey("other user");

        FirmRelayer.Call memory call = _defaultCallWithData(address(target), abi.encodeCall(target.onlySender, (USER)));
        FirmRelayer.RelayRequest memory request = _defaultRequestWithCall(call);
        request.from = otherUser;
        bytes32 hash = relayer.requestTypedDataHash(request);

        bytes memory targetError = abi.encodeWithSelector(RelayTarget.BadSender.selector, USER, otherUser);
        vm.expectRevert(
            abi.encodeWithSelector(FirmRelayer.CallExecutionFailed.selector, 0, address(target), targetError)
        );
        relayer.relay(request, _signPacked(hash, otherUserPk));
    }

    function testRevertOnAssertionFailure() public {
        bytes32 actualReturnValue = bytes32(abi.encode(USER));
        bytes32 badExpectedValue = bytes32(uint256(0));

        FirmRelayer.Call memory call = _defaultCallWithData(address(target), abi.encodeCall(target.onlySender, (USER)));
        FirmRelayer.Assertion memory assertion = FirmRelayer.Assertion(0, badExpectedValue);
        FirmRelayer.RelayRequest memory request = _defaultRequestWithCallAndAssertion(call, assertion);

        bytes32 hash = relayer.requestTypedDataHash(request);
        vm.expectRevert(
            abi.encodeWithSelector(FirmRelayer.AssertionFailed.selector, 0, actualReturnValue, badExpectedValue)
        );
        relayer.relay(request, _signPacked(hash, USER_PK));
    }

    function testRevertOnAssertionOutOfBounds() public {
        FirmRelayer.Call memory call = _defaultCallWithData(address(target), abi.encodeCall(target.onlySender, (USER)));
        FirmRelayer.Assertion memory assertion = FirmRelayer.Assertion(1, bytes32(abi.encode(USER)));
        FirmRelayer.RelayRequest memory request = _defaultRequestWithCallAndAssertion(call, assertion);

        bytes32 hash = relayer.requestTypedDataHash(request);
        vm.expectRevert(abi.encodeWithSelector(FirmRelayer.AssertionPositionOutOfBounds.selector, 0, 32));
        relayer.relay(request, _signPacked(hash, USER_PK));
    }

    function testRevertOnBadAssertionIndex() public {
        FirmRelayer.Call memory call = _defaultCallWithData(address(target), abi.encodeCall(target.onlySender, (USER)));
        FirmRelayer.Assertion memory assertion = FirmRelayer.Assertion(0, bytes32(abi.encode(USER)));
        FirmRelayer.RelayRequest memory request = _defaultRequestWithCallAndAssertion(call, assertion);
        request.calls[0].assertionIndex = 2;

        bytes32 hash = relayer.requestTypedDataHash(request);
        vm.expectRevert(abi.encodeWithSelector(FirmRelayer.BadAssertionIndex.selector, 0));
        relayer.relay(request, _signPacked(hash, USER_PK));
    }

    function testSelfRelay() public {
        FirmRelayer.Call memory call = _defaultCallWithData(address(target), abi.encodeCall(target.onlySender, (USER)));
        FirmRelayer.RelayRequest memory request = _defaultRequestWithCall(call);

        vm.prank(USER);
        relayer.selfRelay(request.calls, request.assertions);

        assertEq(target.lastSender(), USER);
        assertEq(relayer.getNonce(USER), 0);
    }

    function _signPacked(bytes32 hash, uint256 pk) internal pure returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);

        sig = new bytes(65);
        assembly {
            mstore(add(sig, 0x20), r)
            mstore(add(sig, 0x40), s)
            mstore8(add(sig, 0x60), v)
        }
    }

    function _defaultCallWithData(address to, bytes memory data) internal pure returns (FirmRelayer.Call memory call) {
        call.to = to;
        call.data = data;
        call.value = 0;
        call.gas = 10_000_000; // random big value for testing
        call.assertionIndex = 0;
    }

    function _defaultRequestWithCall(FirmRelayer.Call memory call)
        internal
        view
        returns (FirmRelayer.RelayRequest memory request)
    {
        request.from = USER;
        request.nonce = relayer.getNonce(USER);
        request.calls = new FirmRelayer.Call[](1);
        request.calls[0] = call;
    }

    function _defaultRequestWithCallAndAssertion(FirmRelayer.Call memory call, FirmRelayer.Assertion memory assertion)
        internal
        view
        returns (FirmRelayer.RelayRequest memory request)
    {
        request = _defaultRequestWithCall(call);
        request.assertions = new FirmRelayer.Assertion[](1);
        request.assertions[0] = assertion;
        request.calls[0].assertionIndex = 1;
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
