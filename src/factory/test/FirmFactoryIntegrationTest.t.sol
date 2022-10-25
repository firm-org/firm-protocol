// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {GnosisSafe} from "gnosis-safe/GnosisSafe.sol";

import {FirmTest} from "src/common/test/lib/FirmTest.sol";
import {roleFlag} from "src/common/test/mocks/RolesAuthMock.sol";
import {ModuleMock} from "src/common/test/mocks/ModuleMock.sol";

import {Budget, TimeShiftLib, NO_PARENT_ID} from "src/budget/Budget.sol";
import {TimeShift} from "src/budget/TimeShiftLib.sol";
import {Roles, IRoles, IAvatar, ONLY_ROOT_ROLE, ROOT_ROLE_ID} from "src/roles/Roles.sol";
import {FirmRelayer} from "src/metatx/FirmRelayer.sol";
import {SafeEnums} from "src/bases/IZodiacModule.sol";
import {BokkyPooBahsDateTimeLibrary as DateTimeLib} from "datetime/BokkyPooBahsDateTimeLibrary.sol";

import {TestinprodFactory, UpgradeableModuleProxyFactory} from "../TestinprodFactory.sol";
import {LocalDeploy} from "scripts/LocalDeploy.s.sol";
import {TestinprodDeploy, DeployBase} from "scripts/TestinprodDeploy.s.sol";

import {ERC20Token} from "./lib/ERC20Token.sol";
import {IUSDCMinting} from "./lib/IUSDCMinting.sol";

contract FirmFactoryIntegrationTest is FirmTest {
    using TimeShiftLib for *;

    TestinprodFactory factory;
    FirmRelayer relayer;
    ERC20Token token;

    function setUp() public {
        DeployBase deployer;

        if (block.chainid == 1) {
            deployer = new TestinprodDeploy();
            token = ERC20Token(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // mainnet USDC

            IUSDCMinting usdc = IUSDCMinting(address(token));
            vm.prank(usdc.masterMinter()); // master rug
            usdc.configureMinter(address(this), type(uint256).max);
        } else {
            deployer = DeployBase(address(new LocalDeploy()));
            token = new ERC20Token();
        }

        (factory,) = deployer.run();
        relayer = factory.relayer();
    }

    function testFactoryGas() public {
        createFirm(address(this));
    }

    event NewFirmCreated(address indexed creator, GnosisSafe indexed safe, Roles roles, Budget budget);

    function testInitialState() public {
        // we don't match the deployed contract addresses for simplicity (could precalculate them but unnecessary)
        vm.expectEmit(true, false, false, false);
        emit NewFirmCreated(address(this), GnosisSafe(payable(0)), Roles(address(0)), Budget(address(0)));

        (GnosisSafe safe, Budget budget, Roles roles) = createFirm(address(this));

        assertTrue(safe.isModuleEnabled(address(budget)));
        assertTrue(roles.hasRole(address(safe), ROOT_ROLE_ID));
        assertTrue(roles.isTrustedForwarder(address(relayer)));
        assertTrue(budget.isTrustedForwarder(address(relayer)));
    }

    function testExecutingPaymentsFromBudget() public {
        (GnosisSafe safe, Budget budget, Roles roles) = createFirm(address(this));
        token.mint(address(safe), 100);

        (address spender, uint256 spenderPk) = accountAndKey("spender");
        address receiver = account("receiver");

        vm.startPrank(address(safe));
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE, "Executive");
        roles.setRole(spender, roleId, true);

        uint256 allowanceId = budget.createAllowance(
            NO_PARENT_ID, roleFlag(roleId), address(token), 10, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode(), ""
        );
        vm.stopPrank();

        vm.startPrank(spender);
        address[] memory tos = new address[](2);
        tos[0] = receiver;
        tos[1] = receiver;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 4;
        amounts[1] = 1;
        budget.executeMultiPayment(allowanceId, tos, amounts, "");

        vm.warp(block.timestamp + 1 days);
        budget.executePayment(allowanceId, receiver, 9, "");

        vm.expectRevert(abi.encodeWithSelector(Budget.Overbudget.selector, allowanceId, 2, 1));
        budget.executePayment(allowanceId, receiver, 2, "");

        vm.warp(block.timestamp + 1 days);

        // create a suballowance and execute payment from it in a metatx
        uint256 newAllowanceId = allowanceId + 1;
        FirmRelayer.Call[] memory calls = new FirmRelayer.Call[](2);
        calls[0] = FirmRelayer.Call({
            to: address(budget),
            data: abi.encodeCall(
                Budget.createAllowance,
                (allowanceId, spender, address(token), 1, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode(), "")
                ),
            assertionIndex: 1,
            value: 0,
            gas: 1_000_000
        });
        calls[1] = FirmRelayer.Call({
            to: address(budget),
            data: abi.encodeCall(Budget.executePayment, (newAllowanceId, receiver, 1, "")),
            assertionIndex: 0,
            value: 0,
            gas: 1_000_000
        });

        FirmRelayer.Assertion[] memory assertions = new FirmRelayer.Assertion[](1);
        assertions[0] = FirmRelayer.Assertion({position: 0, expectedValue: bytes32(newAllowanceId)});

        FirmRelayer.RelayRequest memory request =
            FirmRelayer.RelayRequest({from: spender, nonce: 0, calls: calls, assertions: assertions});

        relayer.relay(request, _signPacked(relayer.requestTypedDataHash(request), spenderPk));

        assertEq(token.balanceOf(receiver), 15);
    }

    function testModuleUpgrades() public {
        (GnosisSafe safe, Budget budget,) = createFirm(address(this));

        ModuleMock newImpl = new ModuleMock(1);
        vm.prank(address(safe));
        budget.upgrade(newImpl);

        assertEq(ModuleMock(address(budget)).foo(), 1);
    }

    function createFirm(address owner) internal returns (GnosisSafe safe, Budget budget, Roles roles) {
        safe = factory.createFirm(owner, false, 1);
        (address[] memory modules,) = safe.getModulesPaginated(address(0x1), 1);
        budget = Budget(modules[0]);
        roles = Roles(address(budget.roles()));

        vm.label(address(budget), "BudgetProxy");
        vm.label(address(roles), "RolesProxy");
    }

    function _signPacked(bytes32 hash, uint256 pk) internal returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);

        sig = new bytes(65);
        assembly {
            mstore(add(sig, 0x20), r)
            mstore(add(sig, 0x40), s)
            mstore8(add(sig, 0x60), v)
        }
    }
}
