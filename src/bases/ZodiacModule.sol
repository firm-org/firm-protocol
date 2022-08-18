// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {IERC165} from "openzeppelin/interfaces/IERC165.sol";

import {IZodiacModule, IAvatar, IGuard, SafeEnums} from "./IZodiacModule.sol";
import {SafeAware} from "./SafeAware.sol";

/**
 * @title ZodiacModule
 * @dev More minimal implementation of Zodiac's Module.sol without an owner
 *      and using unstructured storage
 * @dev Note that this contract doesn't have an initializer and ZodiacState
 *      must be set explicly if desired, but defaults to being unset
 */
abstract contract ZodiacModule is IZodiacModule, SafeAware {
    struct ZodiacState {
        IAvatar target;
        IGuard guard;
    }

    bytes32 internal constant ZODIAC_STATE_SLOT = // keccak256("firm.zodiacmodule.state") - 2
        0x1bcb284404f22ead428604605be8470a4a8a14c8422630d8a717460f9331147d;

    /**
     * @notice Sets the target of this module to `_target`
     * @dev Unless a target is explictly set through this function, the target is the Safe
     * @param _target The new target to which this module will execute calls
     */
    function setTarget(IAvatar _target) public onlySafe {
        IAvatar previousTarget = target();
        zodiacState().target = _target;
        emit TargetSet(previousTarget, _target);
    }

    /**
     * @notice Set the guard to check transactions of this module to `_guard`
     * @param _guard The address of the guard to be used or 0 to disable the guard
     */
    function setGuard(IGuard _guard) external onlySafe {
        address guardAddr = address(_guard);
        if (guardAddr != address(0)) {
            if (!IERC165(guardAddr).supportsInterface(type(IGuard).interfaceId))
                revert NotIERC165Compliant(guardAddr);
        }
        zodiacState().guard = _guard;
        emit ChangedGuard(guardAddr);
    }

    /**
    * @dev Executes a transaction through the target intended to be executed by the avatar
    * @param to Address being called
    * @param value Ether value being sent
    * @param data Calldata
    * @param operation Operation type of transaction: 0 = call, 1 = delegatecall
    */
    function exec(
        address to,
        uint256 value,
        bytes memory data,
        SafeEnums.Operation operation
    ) internal returns (bool success) {
        IGuard guard_ = guard();
        // If the module has a guard enabled, check if it allows the call
        if (address(guard_) != address(0)) {
            // We zero out data specific to multisig transactions irrelevant in module calls
            guard_.checkTransaction(
                to,
                value,
                data,
                operation,
                0,
                0,
                0,
                address(0),
                payable(0),
                bytes("0x"),
                msg.sender
            );
        }

        // Perform the actual call through the target
        success = target().execTransactionFromModule(
            to,
            value,
            data,
            operation
        );

        // If the module has a guard enabled, notify that the call ocurred and whether it suceeded
        if (address(guard_) != address(0)) {
            guard_.checkAfterExecution(bytes32("0x"), success);
        }
    }

    /**
    * @dev Executes a transaction through the target intended to be executed by the avatar
    *      and returns the call status and the return data of the call
    * @param to Address being called
    * @param value Ether value being sent
    * @param data Calldata
    * @param operation Operation type of transaction: 0 = call, 1 = delegatecall
    */
    function execAndReturnData(
        address to,
        uint256 value,
        bytes memory data,
        SafeEnums.Operation operation
    ) internal returns (bool success, bytes memory returnData) {
        IGuard guard_ = guard();
        // If the module has a guard enabled, check if it allows the call
        if (address(guard_) != address(0)) {
            // We zero out data specific to multisig transactions irrelevant in module calls
            guard_.checkTransaction(
                to,
                value,
                data,
                operation,
                0,
                0,
                0,
                address(0),
                payable(0),
                bytes("0x"),
                msg.sender
            );
        }

        (success, returnData) = target().execTransactionFromModuleReturnData(
            to,
            value,
            data,
            operation
        );

        // If the module has a guard enabled, notify that the call ocurred and whether it suceeded
        if (address(guard_) != address(0)) {
            guard_.checkAfterExecution(bytes32("0x"), success);
        }
    }

    /**
     * @notice Address of the Safe that will ultimately execute module transactions
     */
    function avatar() public view override returns (IAvatar) {
        return safe();
    }

    /**
     * @notice Address of the target contract that this module will execute calls through
     */
    function target() public view override returns (IAvatar) {
        IAvatar target_ = zodiacState().target;
        return address(target_) == address(0) ? safe() : target_;
    }

    /**
     * @notice Address of the guard contract used for additional transaction checks (zero if unset)
     */
    function guard() public view override returns (IGuard) {
        return zodiacState().guard;
    }

    function zodiacState() internal pure returns (ZodiacState storage state) {
        assembly {
            state.slot := ZODIAC_STATE_SLOT
        }
    }
}
