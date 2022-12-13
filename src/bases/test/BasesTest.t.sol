// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "src/common/test/lib/FirmTest.sol";
import {ModuleMock} from "src/common/test/mocks/ModuleMock.sol";
import {SafeStub} from "src/common/test/mocks/SafeStub.sol";
import {UpgradeableModuleProxyFactory} from "src/factory/UpgradeableModuleProxyFactory.sol";

import {ISafe} from "../ISafe.sol";

contract BasesTest is FirmTest {
    UpgradeableModuleProxyFactory factory = new UpgradeableModuleProxyFactory();

    // Parameter in constructor is saved to an immutable variable 'foo'
    ModuleMock moduleOneImpl = new ModuleMock(MODULE_ONE_FOO);

    ModuleMock module;
    SafeStub safe;

    uint256 internal constant MODULE_ONE_FOO = 1;
    uint256 internal constant MODULE_TWO_FOO = 2;
    uint256 internal constant INITIAL_BAR = 3;

    function setUp() public virtual {
        safe = new SafeStub();
        module = ModuleMock(
            factory.deployUpgradeableModule(
                moduleOneImpl, abi.encodeCall(moduleOneImpl.initialize, (safe, INITIAL_BAR)), 0
            )
        );
        vm.label(address(module), "Proxy");
        vm.label(address(moduleOneImpl), "ModuleOne");
    }

    function testCommonRawStorage() public {
        // Bar (first declared storage variable of ModuleMock) is stored on slot 0
        assertEq(uint256(vm.load(address(module), 0)), INITIAL_BAR);
        assertUnsStrg(address(module), "firm.safeaware.safe", address(safe));
    }
}
