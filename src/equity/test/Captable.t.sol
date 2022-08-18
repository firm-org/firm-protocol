// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.13;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import {AvatarStub} from "../../common/test/mocks/AvatarStub.sol";

import {Captable, IBouncer} from "../Captable.sol";
import {EmbeddedBouncersLib} from "../EmbeddedBouncersLib.sol";

contract CaptableTest is FirmTest {
    using EmbeddedBouncersLib for EmbeddedBouncersLib.BouncerType;

    AvatarStub avatar;
    Captable captable;

    address ISSUER = account("issuer");
    address HOLDER_ONE = account("holder #1");
    address HOLDER_TWO = account("holder #2");
    address NOT_HOLDER = account("not holder");

    function setUp() public virtual {
        avatar = new AvatarStub();
        captable = new Captable(
            avatar,
            "Test",
            "TST",
            IBouncer(EmbeddedBouncersLib.BouncerType.AllowAll.addrFlag())
        );
    }

    function testInitialState() public {
        assertEq(address(captable.safe()), address(avatar));
        assertEq(captable.name(), "Test");
        assertEq(captable.symbol(), "TST");
        assertEq(
            address(captable.globalControls()),
            EmbeddedBouncersLib.BouncerType.AllowAll.addrFlag()
        );
    }

    uint256 constant COMMON_AUTHORIZED = 100;

    function testHappyPath() public {
        IBouncer classBouncer = IBouncer(
            EmbeddedBouncersLib.BouncerType.AllowClassHolders.addrFlag()
        );
        address[] memory classIssuers = new address[](1);
        classIssuers[0] = ISSUER;

        vm.prank(address(avatar));
        uint256 classId = captable.createClass(
            "Common",
            0,
            COMMON_AUTHORIZED,
            classBouncer,
            classIssuers
        );
        assertEq(classId, 0);

        vm.prank(ISSUER);
        captable.issue(classId, HOLDER_ONE, 60);
        vm.prank(ISSUER);
        captable.issue(classId, HOLDER_TWO, 30);

        vm.prank(HOLDER_ONE);
        captable.safeTransferFrom(HOLDER_ONE, HOLDER_TWO, classId, 10, "");

        assertEq(captable.balanceOf(HOLDER_ONE, classId), 50);
        assertEq(captable.balanceOf(HOLDER_TWO, classId), 40);

        vm.prank(HOLDER_TWO);
        vm.expectRevert(
            abi.encodeWithSelector(
                Captable.TransferBlocked.selector,
                classBouncer,
                HOLDER_TWO,
                NOT_HOLDER,
                classId,
                10
            )
        );
        captable.safeTransferFrom(HOLDER_TWO, NOT_HOLDER, classId, 10, "");
    }

    function testCustomRevertingBouncer() public {
        // this as bouncer will always revert
        IBouncer revertingBouncer = IBouncer(address(this));
        vm.prank(address(avatar));
        uint256 classId = captable.createClass(
            "Common",
            0,
            COMMON_AUTHORIZED,
            revertingBouncer,
            new address[](0)
        );

        vm.prank(address(avatar));
        captable.issue(classId, HOLDER_ONE, 100);

        vm.prank(HOLDER_ONE);
        vm.expectRevert(
            abi.encodeWithSelector(
                Captable.TransferBlocked.selector,
                revertingBouncer,
                HOLDER_ONE,
                HOLDER_TWO,
                classId,
                10
            )
        );
        captable.safeTransferFrom(HOLDER_ONE, HOLDER_TWO, classId, 10, "");
    }
}

// TODO: CaptableWithProxy
