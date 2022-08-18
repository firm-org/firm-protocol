// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "solmate/utils/Bytes32AddressLib.sol";

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import {ModuleMock} from "../../common/test/mocks/ModuleMock.sol";
import {AvatarStub} from "../../common/test/mocks/AvatarStub.sol";
import {SafeAware, IAvatar} from "../SafeAware.sol";
import {UpgradeableModuleProxyFactory} from "../../factory/UpgradeableModuleProxyFactory.sol";

contract BasesTest is FirmTest {
    using Bytes32AddressLib for bytes32;

    UpgradeableModuleProxyFactory factory = new UpgradeableModuleProxyFactory();

    // Parameter in constructor is saved to an immutable variable 'foo'
    ModuleMock moduleOneImpl = new ModuleMock(MODULE_ONE_FOO);

    ModuleMock module;
    AvatarStub avatar;

    uint256 internal constant MODULE_ONE_FOO = 1;
    uint256 internal constant MODULE_TWO_FOO = 2;
    uint256 internal constant INITIAL_BAR = 3;

    function setUp() public virtual {
        avatar = new AvatarStub();
        module = ModuleMock(
            factory.deployUpgradeableModule(
                address(moduleOneImpl), abi.encodeCall(moduleOneImpl.initialize, (avatar, INITIAL_BAR)), 0
            )
        );
        vm.label(address(module), "Proxy");
        vm.label(address(moduleOneImpl), "ModuleOne");
    }

    function testCommonRawStorage() public {
        // Bar (first declared storage variable of ModuleMock) is stored on slot 0
        assertEq(uint256(vm.load(address(module), 0)), INITIAL_BAR);

        uint256 safeSlot = 0xb2c095c1a3cccf4bf97d6c0d6a44ba97fddb514f560087d9bf71be2c324b6c44;
        assertEq(vm.load(address(module), bytes32(safeSlot)).fromLast20Bytes(), address(avatar));
    }
}
