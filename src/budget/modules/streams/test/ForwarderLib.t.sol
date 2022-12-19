// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "src/common/test/lib/FirmTest.sol";

import "../ForwarderLib.sol";

contract Target {
    mapping(address => bool) public hasHitOnce;

    error AlreadyHit();

    function hit() public payable returns (address sender, uint256 value) {
        if (hasHitOnce[msg.sender]) {
            revert AlreadyHit();
        }

        hasHitOnce[msg.sender] = true;

        return (msg.sender, msg.value);
    }
}

contract ForwarderLibImplementer {
    using ForwarderLib for ForwarderLib.Forwarder;

    function create(bytes32 salt) public returns (ForwarderLib.Forwarder) {
        return ForwarderLib.create(salt);
    }

    function forward(ForwarderLib.Forwarder forwarder, address target, bytes calldata data)
        public
        returns (bool ok, bytes memory ret)
    {
        return forwarder.forward(target, data);
    }

    function forwardChecked(ForwarderLib.Forwarder forwarder, address target, uint256 value, bytes calldata data)
        public
        payable
        returns (bytes memory ret)
    {
        return forwarder.forwardChecked(target, value, data);
    }
}

contract ForwarderLibTest is FirmTest {
    using ForwarderLib for ForwarderLib.Forwarder;

    ForwarderLibImplementer lib;
    Target target;

    bytes32 constant SALT = bytes32(uint256(0xf1f1));

    function setUp() public {
        lib = new ForwarderLibImplementer();
        target = new Target();
    }

    function testCreateForwarder() public returns (ForwarderLib.Forwarder forwarder) {
        forwarder = lib.create(SALT);

        assertGt(forwarder.addr().code.length, 0);
    }

    function testCreatesAtPredictedAddress() public {
        address predictedAddr = ForwarderLib.getForwarder(SALT, address(lib)).addr();
        assertEq(predictedAddr.code.length, 0);

        assertEq(predictedAddr, testCreateForwarder().addr());
    }

    function testRevertsOnRepeatedSalt() public {
        testCreateForwarder();

        vm.expectRevert(ForwarderLib.ForwarderAlreadyDeployed.selector);
        lib.create{gas: 1e6}(SALT);
    }

    function testHitsTarget() public returns (ForwarderLib.Forwarder forwarder) {
        forwarder = testCreateForwarder();

        (bool ok, bytes memory ret) =
            lib.forward(forwarder, address(target), abi.encodeWithSelector(target.hit.selector));

        assertTrue(ok);
        assertTrue(target.hasHitOnce(forwarder.addr()));
        (address sender, uint256 value) = abi.decode(ret, (address, uint256));
        assertEq(sender, forwarder.addr());
        assertEq(value, 0);
        assertEq(address(target).balance, 0);
    }

    function testHitsTargetWithValue() public {
        ForwarderLib.Forwarder forwarder = testCreateForwarder();

        address funder = account("Funder");
        vm.deal(funder, 1 ether);
        vm.prank(funder);
        bytes memory ret = lib.forwardChecked{value: 1 ether}(
            forwarder, address(target), 1 ether, abi.encodeWithSelector(target.hit.selector)
        );

        assertTrue(target.hasHitOnce(forwarder.addr()));
        (address sender, uint256 value) = abi.decode(ret, (address, uint256));
        assertEq(sender, forwarder.addr());
        assertEq(value, 1 ether);
        assertEq(address(target).balance, 1 ether);
    }

    function testForwardTargetRevert() public {
        ForwarderLib.Forwarder forwarder = testHitsTarget();

        // Hitting target again makes it revert
        vm.expectRevert(abi.encodeWithSelector(Target.AlreadyHit.selector));
        lib.forwardChecked(forwarder, address(target), 0, abi.encodeWithSelector(target.hit.selector));
    }

    function testForwardRevertsIfNotOwner() public {
        ForwarderLib.Forwarder forwarder = testCreateForwarder();

        ForwarderLibImplementer lib2 = new ForwarderLibImplementer();

        vm.expectRevert(bytes(""));
        lib2.forwardChecked(forwarder, address(target), 0, abi.encodeWithSelector(target.hit.selector));
    }

    function testLowLevelForward() public {
        ForwarderLib.Forwarder forwarder = testCreateForwarder();

        vm.prank(address(lib));
        (bool ok,) =
            forwarder.addr().call(abi.encodePacked(abi.encodeWithSelector(Target.hit.selector), address(target)));
        assertTrue(ok);
        assertTrue(target.hasHitOnce(forwarder.addr()));
    }

    function testForwardRevertsIfNotEnoughData() public {
        ForwarderLib.Forwarder forwarder = testCreateForwarder();

        vm.prank(address(lib));
        (bool ok, bytes memory ret) = forwarder.addr().call(abi.encodeWithSelector(Target.hit.selector));
        assertFalse(ok);
        assertEq(ret.length, 0);
    }
}
