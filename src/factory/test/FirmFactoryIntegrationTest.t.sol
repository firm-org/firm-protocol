// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {GnosisSafe} from "gnosis-safe/GnosisSafe.sol";

import {FirmTest} from "src/common/test/lib/FirmTest.sol";
import {roleFlag} from "src/common/test/mocks/RolesAuthMock.sol";
import {ModuleMock} from "src/common/test/mocks/ModuleMock.sol";

import {Budget, TimeShiftLib, NO_PARENT_ID, INHERITED_AMOUNT} from "src/budget/Budget.sol";
import {TimeShift} from "src/budget/TimeShiftLib.sol";
import {Roles, IRoles, ISafe, ONLY_ROOT_ROLE_AS_ADMIN, ROOT_ROLE_ID} from "src/roles/Roles.sol";
import {FirmRelayer} from "src/metatx/FirmRelayer.sol";
import {BokkyPooBahsDateTimeLibrary as DateTimeLib} from "datetime/BokkyPooBahsDateTimeLibrary.sol";

import {LlamaPayStreams, BudgetModule, IERC20, ForwarderLib} from "src/budget/modules/streams/LlamaPayStreams.sol";

import {FirmFactory, UpgradeableModuleProxyFactory, LATEST_VERSION} from "../FirmFactory.sol";
import {FirmFactoryDeployLive, FirmFactoryDeployLocal, FirmFactoryDeploy} from "scripts/FirmFactoryDeploy.s.sol";

import {TestnetERC20 as ERC20Token} from "../../testnet/TestnetTokenFaucet.sol";
import {IUSDCMinting} from "./lib/IUSDCMinting.sol";

string constant LLAMAPAYSTREAMS_MODULE_ID = "org.firm.budget.llamapay-streams";

contract FirmFactoryIntegrationTest is FirmTest {
    using TimeShiftLib for *;
    using ForwarderLib for ForwarderLib.Forwarder;

    FirmFactory factory;
    UpgradeableModuleProxyFactory moduleFactory;
    FirmRelayer relayer;
    ERC20Token token;

    function setUp() public {
        FirmFactoryDeploy deployer;

        if (block.chainid == 1) {
            deployer = new FirmFactoryDeployLive();
            token = ERC20Token(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // mainnet USDC

            IUSDCMinting usdc = IUSDCMinting(address(token));
            vm.prank(usdc.masterMinter()); // master rug
            usdc.configureMinter(address(this), type(uint256).max);
        } else {
            deployer = new FirmFactoryDeployLocal();
            token = new ERC20Token("", "", 6);
        }

        (factory, moduleFactory) = deployer.run();
        relayer = factory.relayer();
    }

    function testFactoryGas() public {
        createBarebonesFirm(address(this));
    }

    event NewFirmCreated(address indexed creator, GnosisSafe indexed safe);

    function testInitialState() public {
        // we don't match the deployed contract addresses for simplicity (could precalculate them but unnecessary)
        vm.expectEmit(true, false, false, false);
        emit NewFirmCreated(address(this), GnosisSafe(payable(0)));

        (GnosisSafe safe, Budget budget, Roles roles) = createBarebonesFirm(address(this));

        assertTrue(safe.isModuleEnabled(address(budget)));
        assertTrue(roles.hasRole(address(safe), ROOT_ROLE_ID));
        assertTrue(roles.isTrustedForwarder(address(relayer)));
        assertTrue(budget.isTrustedForwarder(address(relayer)));
    }

    function createFirmWithRoleAndAllowance(address spender) internal returns (GnosisSafe safe, Budget budget, Roles roles) {
        address[] memory safeOwners = new address[](1);
        safeOwners[0] = address(this);
        FirmFactory.SafeConfig memory safeConfig = FirmFactory.SafeConfig(safeOwners, 1);

        uint8 roleId = 2;
        FirmFactory.AllowanceCreationInput[] memory allowances = new FirmFactory.AllowanceCreationInput[](1);
        allowances[0] = FirmFactory.AllowanceCreationInput(
            roleFlag(roleId), address(token), 10, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode(), ""
        );

        address[] memory grantees = new address[](1);
        grantees[0] = spender;
        FirmFactory.RoleCreationInput[] memory rolesCreationInput = new FirmFactory.RoleCreationInput[](1);
        rolesCreationInput[0] = FirmFactory.RoleCreationInput(
            ONLY_ROOT_ROLE_AS_ADMIN, "Executive", grantees
        );
        
        FirmFactory.CaptableConfig memory captableConfig;
        FirmFactory.VotingConfig memory votingConfig;
        FirmFactory.FirmConfig memory firmConfig = FirmFactory.FirmConfig({
            withCaptableAndVoting: false,
            budgetConfig: FirmFactory.BudgetConfig(allowances),
            rolesConfig: FirmFactory.RolesConfig(rolesCreationInput),
            captableConfig: captableConfig,
            votingConfig: votingConfig
        });

        return getFirmAddresses(factory.createFirm(safeConfig, firmConfig, 1));
    }

    function testExecutingPaymentsFromBudget() public {
        (address spender, uint256 spenderPk) = accountAndKey("spender");
        address receiver = account("receiver");
        
        (GnosisSafe safe, Budget budget, Roles roles) = createFirmWithRoleAndAllowance(spender);
        uint256 allowanceId = budget.allowancesCount();

        token.mint(address(safe), 100);

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
        FirmRelayer.RelayRequest memory request;
        {
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

            request =
                FirmRelayer.RelayRequest({from: spender, nonce: 0, calls: calls, assertions: assertions});
        }

        relayer.relay(request, _signPacked(relayer.requestTypedDataHash(request), spenderPk));

        assertEq(token.balanceOf(receiver), 15);
    }

    function testModuleUpgrades() public {
        (GnosisSafe safe, Budget budget,) = createBarebonesFirm(address(this));

        ModuleMock newImpl = new ModuleMock(1);
        vm.prank(address(safe));
        budget.upgrade(newImpl);

        assertEq(ModuleMock(address(budget)).foo(), 1);
    }

    function testBudgetStreaming() public {
        uint256 treasuryAmount = 3e7 * 10 ** token.decimals();
        address receiver = account("Receiver");

        (GnosisSafe safe, Budget budget, Roles roles) = createBarebonesFirm(address(this));
        token.mint(address(safe), treasuryAmount);

        vm.prank(address(safe));
        roles.setRole(address(this), ROOT_ROLE_ID, true);

        vm.prank(address(safe));
        uint256 yearlyAllowanceId = budget.createAllowance(
            NO_PARENT_ID,
            roleFlag(ROOT_ROLE_ID),
            address(token),
            treasuryAmount / 10,
            TimeShift(TimeShiftLib.TimeUnit.Yearly, 0).encode(),
            "Monthly budget"
        );

        LlamaPayStreams streams = LlamaPayStreams(
            moduleFactory.deployUpgradeableModule(
                LLAMAPAYSTREAMS_MODULE_ID,
                LATEST_VERSION,
                abi.encodeCall(BudgetModule.initialize, (budget, address(relayer))),
                1
            )
        );

        uint256 streamAllowanceId = budget.createAllowance(
            yearlyAllowanceId,
            address(streams),
            address(token),
            INHERITED_AMOUNT,
            TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode(),
            "Stream budget"
        );
        streams.configure(streamAllowanceId, 90 days);

        uint256 amountPerSecond = uint256(10_000 * 10 ** 20) / (30 days);
        streams.startStream(streamAllowanceId, receiver, amountPerSecond, "Receiver salary");
        timetravel(30 days);

        uint256 newAmountPerSecond = amountPerSecond / 2;
        streams.modifyStream(streamAllowanceId, receiver, amountPerSecond, receiver, newAmountPerSecond);
        timetravel(30 days);

        streams.streamerForToken(IERC20(address(token))).withdraw(
            streams.forwarderForAllowance(streamAllowanceId).addr(), receiver, uint216(newAmountPerSecond)
        );

        assertApproxEqAbs(token.balanceOf(receiver), 15_000 * 10 ** token.decimals(), 2);
    }

    function createBarebonesFirm(address owner) internal returns (GnosisSafe safe, Budget budget, Roles roles) {
        return getFirmAddresses(factory.createBarebonesFirm(owner, 1));
    }

    function getFirmAddresses(GnosisSafe safe) internal returns (GnosisSafe _safe, Budget budget, Roles roles) {
        (address[] memory modules,) = safe.getModulesPaginated(address(0x1), 1);
        budget = Budget(modules[0]);
        roles = Roles(address(budget.roles()));
        _safe = safe;

        vm.label(address(budget), "BudgetProxy");
        vm.label(address(roles), "RolesProxy");
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
}
