// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {FirmTest} from "src/bases/test/lib/FirmTest.sol";
import {SafeStub} from "src/bases/test/mocks/SafeStub.sol";
import {SafeAware} from "src/bases/SafeAware.sol";
import {AddressUint8FlagsLib} from "src/bases/utils/AddressUint8FlagsLib.sol";
import {Roles, ONLY_ROOT_ROLE_AS_ADMIN} from "src/roles/Roles.sol";
import {roleFlag} from "src/bases/test/mocks/RolesAuthMock.sol";

import {Captable, IBouncer, NO_CONVERSION_FLAG, NO_CONTROLLER} from "../Captable.sol";
import {EquityToken} from "../EquityToken.sol";
import {EmbeddedBouncerType, EMBEDDED_BOUNCER_FLAG_TYPE} from "../BouncerChecker.sol";
import {VestingController} from "../controllers/VestingController.sol";
import {DisallowController} from "./mocks/DisallowController.sol";
import {OddBouncer} from "./mocks/OddBouncer.sol";

contract BaseCaptableTest is FirmTest {
    using AddressUint8FlagsLib for *;

    Captable captable;
    VestingController vesting;
    Roles roles;
    SafeStub safe = new SafeStub();

    IBouncer ALLOW_ALL_BOUNCER = embeddedBouncer(EmbeddedBouncerType.AllowAll);

    address HOLDER1 = account("Holder #1");
    address HOLDER2 = account("Holder #2");
    address ISSUER = account("Issuer");
    address VESTING_REVOKER = account("Vesting Revoker");

    address VESTING_REVOKER_ROLE_FLAG;

    function setUp() public virtual {
        captable =
            Captable(createProxy(new Captable(), abi.encodeCall(Captable.initialize, ("TestCo", safe, address(0)))));
        roles = Roles(createProxy(new Roles(), abi.encodeCall(Roles.initialize, (safe, address(0)))));
        vesting = VestingController(
            createProxy(
                new VestingController(), abi.encodeCall(VestingController.initialize, (captable, roles, address(0)))
            )
        );

        vm.startPrank(address(safe));
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "Vesting revoking");
        roles.setRole(VESTING_REVOKER, roleId, true);
        VESTING_REVOKER_ROLE_FLAG = roleFlag(roleId);
        vm.stopPrank();
    }

    // votes only count when a delegation is set
    function _selfDelegateHolders(EquityToken token) internal {
        vm.prank(HOLDER1);
        token.delegate(HOLDER1);
        vm.prank(HOLDER2);
        token.delegate(HOLDER2);
    }

    function embeddedBouncer(EmbeddedBouncerType bouncerType) internal pure returns (IBouncer) {
        return IBouncer(uint8(bouncerType).toFlag(EMBEDDED_BOUNCER_FLAG_TYPE));
    }
}

contract CaptableInitTest is BaseCaptableTest {
    function testInitialState() public {
        // Create a new one to ensure proper coverage of initialize()
        captable =
            Captable(createProxy(new Captable(), abi.encodeCall(Captable.initialize, ("TestCo1", safe, address(0)))));

        assertEq(address(captable.safe()), address(safe));
        assertEq(captable.name(), "TestCo1");

        assertEq(captable.numberOfClasses(), 0);

        bytes memory unexistentError = abi.encodeWithSelector(Captable.UnexistentClass.selector, 0);
        vm.expectRevert(unexistentError);
        captable.nameFor(0);
        vm.expectRevert(unexistentError);
        captable.tickerFor(0);
    }

    function testCannotReinit() public {
        vm.expectRevert(abi.encodeWithSelector(SafeAware.AlreadyInitialized.selector));
        captable.initialize("", safe, address(1));
    }

    function testCreateClass() public {
        vm.prank(address(safe));
        (uint256 id, EquityToken token) =
            captable.createClass("Common", "TST-A", 100, NO_CONVERSION_FLAG, 1, ALLOW_ALL_BOUNCER);
        assertEq(id, 0);

        assertEq(token.name(), "TestCo: Common");
        assertEq(token.symbol(), "TST-A");
        assertEq(token.totalSupply(), 0);
        assertEq(token.decimals(), 18);

        (
            EquityToken token_,
            uint64 votingWeight,
            uint32 convertsToClassId,
            uint256 authorized,
            uint256 convertible,
            string memory name,
            string memory ticker,
            IBouncer bouncer,
            bool isFrozen
        ) = captable.classes(id);
        assertEq(address(token_), address(token));
        assertEq(votingWeight, 1);
        assertEq(convertsToClassId, NO_CONVERSION_FLAG);
        assertEq(authorized, 100);
        assertEq(convertible, 0);
        assertEq(name, "Common");
        assertEq(ticker, "TST-A");
        assertEq(address(bouncer), address(ALLOW_ALL_BOUNCER));
        assertEq(isFrozen, false);
    }

    function testCannotCreateMoreClassesThanLimit() public {
        uint256 CLASSES_LIMIT = 128;

        for (uint256 i = 0; i < CLASSES_LIMIT; i++) {
            vm.prank(address(safe));
            captable.createClass("", "", 1, NO_CONVERSION_FLAG, 0, ALLOW_ALL_BOUNCER);
        }
        assertEq(captable.numberOfClasses(), CLASSES_LIMIT);

        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.ClassCreationAboveLimit.selector));
        captable.createClass("", "", 1, NO_CONVERSION_FLAG, 0, ALLOW_ALL_BOUNCER);
    }

    function testCantCreateClassWithZeroAuthorized() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.BadInput.selector));
        captable.createClass("", "", 0, NO_CONVERSION_FLAG, 0, ALLOW_ALL_BOUNCER);
    }

    function testCantCreateClassWithZeroAddressBouncer() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.BadInput.selector));
        captable.createClass("", "", 1, NO_CONVERSION_FLAG, 0, IBouncer(address(0)));
    }
}

contract CaptableOneClassTest is BaseCaptableTest {
    EquityToken token;
    uint256 classId;

    uint256 constant INITIAL_AUTHORIZED = 10000;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(address(safe));
        (classId, token) =
            captable.createClass("Common", "TST-A", INITIAL_AUTHORIZED, NO_CONVERSION_FLAG, 1, ALLOW_ALL_BOUNCER);
        captable.setManager(classId, ISSUER, true);
        vm.stopPrank();
    }

    function testManagerCanIssue(uint256 amount) public {
        vm.assume(amount > 0 && amount <= INITIAL_AUTHORIZED);
        vm.prank(ISSUER);
        captable.issue(HOLDER1, classId, amount);
        assertEq(token.balanceOf(HOLDER1), amount);
        assertEq(token.totalSupply(), amount);

        vm.prank(HOLDER1);
        token.transfer(HOLDER2, 1);
        assertEq(token.balanceOf(HOLDER2), 1);

        assertEq(captable.issuedFor(classId), amount);
    }

    function testCantIssueAboveAuthorized() public {
        vm.prank(ISSUER);
        vm.expectRevert(abi.encodeWithSelector(Captable.IssuedOverAuthorized.selector, classId));
        captable.issue(HOLDER1, classId, INITIAL_AUTHORIZED + 1);
    }

    function testCantIssueIfNotManager() public {
        vm.prank(address(safe));
        captable.setManager(classId, ISSUER, false);
        vm.prank(ISSUER);
        vm.expectRevert(abi.encodeWithSelector(Captable.UnauthorizedNotManager.selector, classId));
        captable.issue(HOLDER1, classId, 1);
    }

    function testCantIssueZeroShares() public {
        vm.prank(ISSUER);
        vm.expectRevert(abi.encodeWithSelector(Captable.BadInput.selector));
        captable.issue(HOLDER1, classId, 0);
    }

    function testCanChangeAuthorized() public {
        uint256 newAuthorized = INITIAL_AUTHORIZED + 1000;
        vm.prank(address(safe));
        captable.setAuthorized(classId, newAuthorized);
        assertEq(captable.authorizedFor(classId), newAuthorized);
    }

    function testCantChangeAuthorizedIfNotSafe() public {
        vm.expectRevert(abi.encodeWithSelector(SafeAware.UnauthorizedNotSafe.selector));
        captable.setAuthorized(classId, INITIAL_AUTHORIZED + 1);
    }

    function testCantChangeAuthorizedToZero() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.BadInput.selector));
        captable.setAuthorized(classId, 0);
    }

    function testCantChangeAuthorizedBelowIssued() public {
        vm.prank(ISSUER);
        captable.issue(HOLDER1, classId, INITIAL_AUTHORIZED);
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.IssuedOverAuthorized.selector, classId));
        captable.setAuthorized(classId, INITIAL_AUTHORIZED - 1);
    }

    function testCanIssueWithVesting() public {
        uint256 amount = INITIAL_AUTHORIZED;

        VestingController.VestingParams memory vestingParams;
        vestingParams.startDate = 100;
        vestingParams.cliffDate = 120;
        vestingParams.endDate = 200;

        vm.prank(ISSUER);
        captable.issueAndSetController(HOLDER1, classId, amount, vesting, abi.encode(vestingParams));

        assertVesting(amount, vestingParams);
    }

    function testManagerCanRetroactivelyAddVesting() public {
        uint256 amount = INITIAL_AUTHORIZED;

        VestingController.VestingParams memory vestingParams;
        vestingParams.startDate = 100;
        vestingParams.cliffDate = 120;
        vestingParams.endDate = 200;

        vm.startPrank(ISSUER);
        captable.issue(HOLDER1, classId, amount);
        captable.setController(HOLDER1, classId, vesting, abi.encode(vestingParams));
        vm.stopPrank();

        assertVesting(amount, vestingParams);
    }

    function assertVesting(uint256 amount, VestingController.VestingParams memory vestingParams) internal {
        assertEq(token.balanceOf(HOLDER1), amount);

        vm.startPrank(HOLDER1);
        vm.warp(vestingParams.startDate - 1);
        vm.expectRevert(
            abi.encodeWithSelector(Captable.TransferBlocked.selector, vesting, HOLDER1, HOLDER2, classId, 1)
        );
        token.transfer(HOLDER2, 1);

        vm.warp(vestingParams.cliffDate);
        token.transfer(HOLDER2, 1);
        assertEq(token.balanceOf(HOLDER2), 1);

        vm.warp(vestingParams.endDate);
        token.transfer(HOLDER2, token.balanceOf(HOLDER1));
        assertEq(token.balanceOf(HOLDER2), amount);
    }

    function testCanRevokeVesting() public {
        uint256 amount = 100;

        VestingController.VestingParams memory vestingParams;
        vestingParams.startDate = 100;
        vestingParams.cliffDate = 100;
        vestingParams.endDate = 200;
        vestingParams.revoker = VESTING_REVOKER_ROLE_FLAG;

        vm.prank(ISSUER);
        captable.issueAndSetController(HOLDER1, classId, amount, vesting, abi.encode(vestingParams));
        assertEq(token.balanceOf(HOLDER1), amount);
        assertEq(address(captable.controllers(HOLDER1, classId)), address(vesting));

        vm.warp(150);
        vm.prank(address(VESTING_REVOKER));
        vesting.revokeVesting(HOLDER1, classId, 150);

        assertEq(token.balanceOf(HOLDER1), amount / 2);
        assertEq(token.balanceOf(address(safe)), amount / 2);

        assertEq(address(captable.controllers(HOLDER1, classId)), address(NO_CONTROLLER));
    }

    function testNonManagerCannotAddController() public {
        vm.expectRevert(abi.encodeWithSelector(Captable.UnauthorizedNotManager.selector, classId));
        captable.setController(HOLDER1, classId, vesting, "");
    }

    function testNonControllerCannotForceTransfer() public {
        vm.expectRevert(abi.encodeWithSelector(Captable.UnauthorizedNotController.selector, classId));
        captable.controllerForcedTransfer(HOLDER1, HOLDER2, classId, 1, "");
    }

    function testManagerCanForceTransfer() public {
        vm.prank(ISSUER);
        captable.issue(HOLDER1, classId, 100);
        assertEq(token.balanceOf(HOLDER1), 100);

        vm.prank(ISSUER);
        captable.managerForcedTransfer(HOLDER1, HOLDER2, classId, 1, "");
        assertEq(token.balanceOf(HOLDER1), 99);
        assertEq(token.balanceOf(HOLDER2), 1);
    }

    function testNonManagerCannotForceTransfer() public {
        vm.expectRevert(abi.encodeWithSelector(Captable.UnauthorizedNotManager.selector, classId));
        captable.managerForcedTransfer(HOLDER1, HOLDER2, classId, 1, "");
    }

    function testSafeCanFreeze() public {
        vm.prank(address(safe));
        captable.freeze(classId);
        (,,,,,,,, bool isFrozen) = captable.classes(classId);
        assertTrue(isFrozen);
    }

    function testNonSafeCannotFreeze() public {
        vm.expectRevert(abi.encodeWithSelector(SafeAware.UnauthorizedNotSafe.selector));
        captable.freeze(classId);
    }
}

contract CaptableFrozenTest is BaseCaptableTest {
    uint256 classId;
    EquityToken token;
    uint256 constant INITIAL_AUTHORIZED = 1000;

    function setUp() public override {
        super.setUp();

        vm.startPrank(address(safe));
        (classId, token) =
            captable.createClass("Common", "TST-A", INITIAL_AUTHORIZED, NO_CONVERSION_FLAG, 1, ALLOW_ALL_BOUNCER);
        captable.setManager(classId, ISSUER, true);
        captable.freeze(classId);
        vm.stopPrank();
    }

    // Functionality that still works post class freeze

    function testCanIssueAndTransfer() public {
        vm.prank(ISSUER);
        captable.issue(HOLDER1, classId, 100);
        assertEq(token.balanceOf(HOLDER1), 100);

        vm.prank(HOLDER1);
        token.transfer(HOLDER2, 100);
    }

    function testCanIssueAndRevokeVesting() public {
        uint256 amount = 100;

        VestingController.VestingParams memory vestingParams;
        vestingParams.startDate = 100;
        vestingParams.cliffDate = 100;
        vestingParams.endDate = 200;
        vestingParams.revoker = VESTING_REVOKER_ROLE_FLAG;

        vm.prank(ISSUER);
        captable.issueAndSetController(HOLDER1, classId, amount, vesting, abi.encode(vestingParams));
        assertEq(token.balanceOf(HOLDER1), amount);

        vm.warp(150);
        vm.prank(address(safe)); // safe also has role as root role holder
        vesting.revokeVesting(HOLDER1, classId, 150);

        assertEq(token.balanceOf(HOLDER1), amount / 2);
        assertEq(token.balanceOf(address(safe)), amount / 2);
    }

    function testCanCreateConvertingClassIssueAndConvert() public {
        vm.prank(address(safe));
        (uint256 classId2,) = captable.createClass("", "", 100, uint32(classId), 1, ALLOW_ALL_BOUNCER);

        vm.prank(address(safe));
        captable.setManager(classId2, ISSUER, true);

        vm.prank(ISSUER);
        captable.issue(HOLDER1, classId2, 100);

        vm.prank(HOLDER1);
        captable.convert(classId2, 100);
        assertEq(token.balanceOf(HOLDER1), 100);
    }

    // Functionality that no longer works post class freeze

    function testCantChangeAuthorized() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.FrozenClass.selector, classId));
        captable.setAuthorized(classId, 100);
    }

    function testCantChangeManagers() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.FrozenClass.selector, classId));
        captable.setManager(classId, ISSUER, false);
    }

    function testCantFreezeAgain() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.FrozenClass.selector, classId));
        captable.freeze(classId);
    }

    function testCantChangeBouncer() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.FrozenClass.selector, classId));
        captable.setBouncer(classId, embeddedBouncer(EmbeddedBouncerType.DenyAll));
    }
}

contract CaptableMulticlassTest is BaseCaptableTest {
    uint256 classId1;
    EquityToken token1;
    uint64 weight1 = 1;
    uint256 authorized1 = 2000;

    uint256 classId2;
    EquityToken token2;
    uint64 weight2 = 5;
    uint256 authorized2 = 1000;

    uint256 holder1InitialBalance1 = 100;
    uint256 holder1InitialBalance2 = 100;

    uint256 holder2InitialBalance1 = 0;
    uint256 holder2InitialBalance2 = 150;

    function setUp() public override {
        super.setUp();

        vm.startPrank(address(safe));
        (classId1, token1) =
            captable.createClass("Common", "TST-A", authorized1, NO_CONVERSION_FLAG, weight1, ALLOW_ALL_BOUNCER);
        (classId2, token2) =
            captable.createClass("Founder", "TST-B", authorized2, uint32(classId1), weight2, ALLOW_ALL_BOUNCER);
        captable.setManager(classId1, ISSUER, true);
        captable.setManager(classId2, ISSUER, true);
        vm.stopPrank();

        _selfDelegateHolders(token1);
        _selfDelegateHolders(token2);

        vm.roll(2); // set block number to 2
        _issueInitialShares();
    }

    function testInitialState() public {
        (, uint64 votingWeight1, uint32 convertsToClassId1, uint256 _authorized1, uint256 convertible1,,,,) =
            captable.classes(classId1);
        (, uint64 votingWeight2, uint32 convertsToClassId2, uint256 _authorized2, uint256 convertible2,,,,) =
            captable.classes(classId2);

        assertEq(votingWeight1, weight1);
        assertEq(convertsToClassId1, NO_CONVERSION_FLAG);
        assertEq(_authorized1, authorized1);
        assertEq(convertible1, authorized2);

        assertEq(votingWeight2, weight2);
        assertEq(convertsToClassId2, classId1);
        assertEq(_authorized2, authorized2);
        assertEq(convertible2, 0);
    }

    function testVotingWeights() public {
        vm.roll(3);

        assertEq(captable.getVotes(HOLDER1), holder1InitialBalance1 + holder1InitialBalance2 * weight2);
        assertEq(captable.getVotes(HOLDER2), holder2InitialBalance2 * weight2);
        assertEq(
            captable.getTotalVotes(),
            holder1InitialBalance1 + (holder1InitialBalance1 + holder2InitialBalance2) * weight2
        );

        assertEq(captable.getPastVotes(HOLDER1, 1), 0);
        assertEq(captable.getPastVotes(HOLDER2, 1), 0);
        assertEq(captable.getPastTotalSupply(1), 0);

        assertEq(captable.getPastVotes(HOLDER1, 2), holder1InitialBalance1 + holder1InitialBalance2 * weight2);
        assertEq(captable.getPastVotes(HOLDER2, 2), holder2InitialBalance2 * weight2);
        assertEq(
            captable.getPastTotalSupply(2),
            holder1InitialBalance1 + (holder1InitialBalance1 + holder2InitialBalance2) * weight2
        );
    }

    function testVotesUpdateOnTransfer() public {
        vm.roll(3);

        vm.prank(HOLDER1);
        token1.transfer(HOLDER2, 50);

        assertEq(captable.getVotes(HOLDER1), holder1InitialBalance1 - 50 + holder1InitialBalance2 * weight2);
        assertEq(captable.getVotes(HOLDER2), 50 + holder2InitialBalance2 * weight2);

        // at height 2, balances stay unchanged
        assertEq(captable.getPastVotes(HOLDER1, 2), holder1InitialBalance1 + holder1InitialBalance2 * weight2);
        assertEq(captable.getPastVotes(HOLDER2, 2), holder2InitialBalance2 * weight2);
    }

    function testConvertBetweenClasses() public {
        vm.roll(3);

        assertEq(captable.getVotes(HOLDER2), holder2InitialBalance2 * weight2);

        vm.prank(HOLDER2);
        captable.convert(classId2, holder2InitialBalance2);

        assertEq(captable.getVotes(HOLDER2), holder2InitialBalance2);

        assertEq(token2.balanceOf(HOLDER2), 0);
        assertEq(token1.balanceOf(HOLDER2), holder2InitialBalance2);
    }

    function testCantCreateConvertibleClassIfNotEnoughAuthorized() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.ConvertibleOverAuthorized.selector, classId2));
        captable.createClass("", "", 1000, uint32(classId2), 1, ALLOW_ALL_BOUNCER);
    }

    function testChangingAuthorizedUpdatesConvertibleToLimit()
        public
        returns (uint256 newAuthorized1, uint256 newAuthorized2)
    {
        // authorize to the limit
        newAuthorized2 = holder1InitialBalance2 + holder2InitialBalance2;
        newAuthorized1 = newAuthorized2 + holder1InitialBalance1 + holder2InitialBalance1;
        vm.prank(address(safe));
        captable.setAuthorized(classId2, newAuthorized2);
        vm.prank(address(safe));
        captable.setAuthorized(classId1, newAuthorized1);
        (,,, uint256 _authorized1, uint256 convertible1,,,,) = captable.classes(classId1);
        (,,, uint256 _authorized2, uint256 convertible2,,,,) = captable.classes(classId2);

        assertEq(_authorized1, newAuthorized1);
        assertEq(_authorized2, newAuthorized2);
        assertEq(convertible1, newAuthorized2);
        assertEq(convertible2, 0);
    }

    function testWhenOnConvertibleLimitCantAuthorizeLessOnConverting() public {
        (uint256 newAuthorized1,) = testChangingAuthorizedUpdatesConvertibleToLimit();
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.IssuedOverAuthorized.selector, classId1));
        captable.setAuthorized(classId1, newAuthorized1 - 1);
    }

    function testWhenOnConvertibleLimitCantAuthorizeMoreOnConverter() public {
        (, uint256 newAuthorized2) = testChangingAuthorizedUpdatesConvertibleToLimit();
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.ConvertibleOverAuthorized.selector, classId1));
        captable.setAuthorized(classId2, newAuthorized2 + 1);
    }

    function testWhenOnConvertibleLimitCantIssueMore() public {
        testChangingAuthorizedUpdatesConvertibleToLimit();
        vm.prank(ISSUER);
        vm.expectRevert(abi.encodeWithSelector(Captable.IssuedOverAuthorized.selector, classId1));
        captable.issue(HOLDER1, classId1, 1);
    }

    function testCantChangeAuthorizedIfNotEnoughOnConvertingClass() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.ConvertibleOverAuthorized.selector, classId1));
        captable.setAuthorized(classId2, authorized1);
    }

    function testCantConvertIfControllerDisallows() public {
        DisallowController controller = new DisallowController();

        // This rogue controller starts controlling all of HOLDER2's classId2 shares
        vm.prank(ISSUER);
        captable.issueAndSetController(HOLDER2, classId2, 1, controller, "");

        vm.prank(HOLDER2);
        vm.expectRevert(abi.encodeWithSelector(Captable.ConversionBlocked.selector, controller, HOLDER2, classId2, 1));
        captable.convert(classId2, 1);
    }

    function _issueInitialShares() internal {
        vm.startPrank(ISSUER);
        captable.issue(HOLDER1, classId1, holder1InitialBalance1);
        captable.issue(HOLDER1, classId2, holder1InitialBalance2);
        // captable.issue(HOLDER2, classId1, holder2InitialBalance1); // issuing 0 fails
        captable.issue(HOLDER2, classId2, holder2InitialBalance2);
        vm.stopPrank();
    }
}

contract CaptableClassLimit1Test is BaseCaptableTest {
    uint256 constant classesLimit = 128;
    uint256 constant transfersLimit = 64;

    // Holder gets token in each of the classes
    function setUp() public override {
        super.setUp();

        for (uint256 i = 0; i < classesLimit; i++) {
            vm.roll(0);
            vm.prank(address(safe));
            (uint256 classId, EquityToken token) =
                captable.createClass("", "", transfersLimit, NO_CONVERSION_FLAG, 1, ALLOW_ALL_BOUNCER);
            _selfDelegateHolders(token);

            // Artificially create checkpoints by issuing one share per block
            for (uint256 j = 0; j < transfersLimit; j++) {
                vm.roll(j);
                vm.prank(address(safe));
                captable.issue(HOLDER1, classId, 1);
            }
        }
    }

    function testGetVotesGas() public {
        vm.roll(transfersLimit);
        assertEq(captable.getVotes(HOLDER1), classesLimit * transfersLimit);
    }

    function testGetTotalVotesGas() public {
        vm.roll(transfersLimit);
        assertEq(captable.getTotalVotes(), classesLimit * transfersLimit);
    }

    function testGetPastVotesGas() public {
        vm.roll(transfersLimit);
        // look for a checkpoint close to the worst case in the binary search
        assertEq(captable.getPastVotes(HOLDER1, transfersLimit - 2), classesLimit * (transfersLimit - 1));
    }

    function testGetPastTotalSupplyGas() public {
        vm.roll(transfersLimit);
        // look for a checkpoint close to the worst case in the binary search
        assertEq(captable.getPastTotalSupply(transfersLimit - 2), classesLimit * (transfersLimit - 1));
    }
}

contract CaptableClassLimit2Test is BaseCaptableTest {
    uint256 constant classesLimit = 128;
    uint256 constant transfersLimit = 64;

    // Holder just has tokens in one class
    function setUp() public override {
        super.setUp();

        for (uint256 i = 0; i < classesLimit; i++) {
            vm.roll(0);
            vm.prank(address(safe));
            (uint256 classId, EquityToken token) =
                captable.createClass("", "", transfersLimit, NO_CONVERSION_FLAG, 1, ALLOW_ALL_BOUNCER);
            _selfDelegateHolders(token);

            if (i == 0) {
                for (uint256 j = 0; j < transfersLimit; j++) {
                    vm.roll(j);
                    vm.prank(address(safe));
                    captable.issue(HOLDER1, classId, 1);
                }
            }
        }
    }

    function testGetVotesGas() public {
        vm.roll(transfersLimit);
        assertEq(captable.getVotes(HOLDER1), transfersLimit);
    }

    function testGetTotalVotesGas() public {
        vm.roll(transfersLimit);
        assertEq(captable.getTotalVotes(), transfersLimit);
    }

    function testGetPastVotesGas() public {
        vm.roll(transfersLimit);
        // look for a checkpoint close to the worst case in the binary search
        assertEq(captable.getPastVotes(HOLDER1, transfersLimit - 2), transfersLimit - 1);
    }

    function testGetPastTotalSupplyGas() public {
        vm.roll(transfersLimit);
        // look for a checkpoint close to the worst case in the binary search
        assertEq(captable.getPastTotalSupply(transfersLimit - 2), transfersLimit - 1);
    }
}

contract CaptableBouncersTest is BaseCaptableTest {
    using AddressUint8FlagsLib for *;

    uint256 classId;
    EquityToken token;

    uint256 initialHolder1Balance = 100;

    function setUp() public override {
        super.setUp();

        // Create a class with AllowAll as the initial bouncer
        vm.prank(address(safe));
        (classId, token) = captable.createClass("", "", 1000, NO_CONVERSION_FLAG, 1, ALLOW_ALL_BOUNCER);

        // Issue some tokens to HOLDER1
        vm.prank(address(safe));
        captable.issue(HOLDER1, classId, initialHolder1Balance);
    }

    function testAllowAllBouncer() public {
        // No need to set the bouncer, it was as allow all initially
        vm.prank(HOLDER1);
        token.transfer(HOLDER2, 10);
        assertEq(token.balanceOf(HOLDER1), initialHolder1Balance - 10);
        assertEq(token.balanceOf(HOLDER2), 10);

        vm.prank(HOLDER2);
        token.transfer(HOLDER1, 5);
        assertEq(token.balanceOf(HOLDER1), initialHolder1Balance - 5);
        assertEq(token.balanceOf(HOLDER2), 5);
    }

    function testDenyAllBouncer() public {
        IBouncer bouncer = embeddedBouncer(EmbeddedBouncerType.DenyAll);
        vm.prank(address(safe));
        captable.setBouncer(classId, bouncer);

        // HOLDER1 can't transfer
        vm.prank(HOLDER1);
        vm.expectRevert(
            abi.encodeWithSelector(Captable.TransferBlocked.selector, bouncer, HOLDER1, HOLDER2, classId, 10)
        );
        token.transfer(HOLDER2, 10);

        // Even if HOLDER2 transfers to HOLDER1 who is already a holder
        vm.prank(address(safe));
        captable.issue(HOLDER2, classId, 1);
        vm.prank(HOLDER2);
        vm.expectRevert(
            abi.encodeWithSelector(Captable.TransferBlocked.selector, bouncer, HOLDER2, HOLDER1, classId, 1)
        );
        token.transfer(HOLDER1, 1);
    }

    function testClassHoldersOnlyBouncer() public {
        IBouncer bouncer = embeddedBouncer(EmbeddedBouncerType.AllowTransferToClassHolder);
        vm.prank(address(safe));
        captable.setBouncer(classId, bouncer);

        // HOLDER1 can't transfer to HOLDER2 as it is not a holder of the class
        vm.prank(HOLDER1);
        vm.expectRevert(
            abi.encodeWithSelector(Captable.TransferBlocked.selector, bouncer, HOLDER1, HOLDER2, classId, 10)
        );
        token.transfer(HOLDER2, 10);

        // If we make HOLDER2 a holder, it can now receive from HOLDER1
        vm.prank(address(safe));
        captable.issue(HOLDER2, classId, 1);

        vm.prank(HOLDER1);
        token.transfer(HOLDER2, 1);

        assertEq(token.balanceOf(HOLDER2), 2);
    }

    function testHoldersOnlyBouncer() public {
        IBouncer bouncer = embeddedBouncer(EmbeddedBouncerType.AllowTransferToAllHolders);
        vm.prank(address(safe));
        captable.setBouncer(classId, bouncer);

        // HOLDER1 can't transfer to HOLDER2 as it is not a holder of any class
        vm.prank(HOLDER1);
        vm.expectRevert(
            abi.encodeWithSelector(Captable.TransferBlocked.selector, bouncer, HOLDER1, HOLDER2, classId, 10)
        );
        token.transfer(HOLDER2, 10);

        // We create a new class and make HOLDER2 a holder of that class so it can receive shares of the first class
        vm.prank(address(safe));
        (uint256 classId2,) = captable.createClass("", "", 1000, NO_CONVERSION_FLAG, 1, ALLOW_ALL_BOUNCER);
        vm.prank(address(safe));
        captable.issue(HOLDER2, classId2, 1);

        vm.prank(HOLDER1);
        token.transfer(HOLDER2, 1);
        assertEq(token.balanceOf(HOLDER2), 1);
    }

    function testFailsOnNonExistentEmbeddedBouncer() public {
        IBouncer badBouncer = IBouncer(uint8(100).toFlag(EMBEDDED_BOUNCER_FLAG_TYPE));
        vm.prank(address(safe));
        captable.setBouncer(classId, badBouncer);

        vm.prank(HOLDER1);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Conversion into non-existent enum type"));
        token.transfer(HOLDER2, 10);
    }

    function testFailsOnBadFlagForEmbeddedBouncer() public {
        IBouncer badBouncer = IBouncer(uint8(EmbeddedBouncerType.AllowAll).toFlag(0x10));
        vm.prank(address(safe));
        captable.setBouncer(classId, badBouncer);

        vm.prank(HOLDER1);
        vm.expectRevert("EvmError: Revert");
        token.transfer(HOLDER2, 10);
    }

    function testCustomBouncer() public {
        IBouncer bouncer = new OddBouncer();
        vm.prank(address(safe));
        captable.setBouncer(classId, bouncer);

        // Bouncer allows transferring 1 because it is odd
        vm.prank(HOLDER1);
        token.transfer(HOLDER2, 1);
        assertEq(token.balanceOf(HOLDER2), 1);

        // Bouncer doesn't allow transferring 2 because it is even
        vm.prank(HOLDER1);
        vm.expectRevert(
            abi.encodeWithSelector(Captable.TransferBlocked.selector, bouncer, HOLDER1, HOLDER2, classId, 2)
        );
        token.transfer(HOLDER2, 2);
    }

    function testCantSetBouncerIfNotSafe() public {
        vm.prank(HOLDER1);
        vm.expectRevert(abi.encodeWithSelector(SafeAware.UnauthorizedNotSafe.selector));
        captable.setBouncer(classId, embeddedBouncer(EmbeddedBouncerType.DenyAll));
    }

    function testCantSetBouncerToZeroAddr() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.BadInput.selector));
        captable.setBouncer(classId, IBouncer(address(0)));
    }
}
