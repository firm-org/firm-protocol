// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "zodiac/interfaces/IAvatar.sol";
import "zodiac/interfaces/IGuard.sol";
import "zodiac/guard/BaseGuard.sol";

import "./SafeAware.sol";

abstract contract IZodiacModule {
    event AvatarSet(IAvatar indexed previousAvatar, IAvatar indexed newAvatar);
    event TargetSet(IAvatar indexed previousTarget, IAvatar indexed newTarget);
    event ChangedGuard(address guard);

    error NotIERC165Compliant(address guard_);

    function avatar() public view virtual returns (IAvatar);

    function target() public view virtual returns (IAvatar);

    function guard() public view virtual returns (IGuard);
}

/**
 * @title ZodiacModule
 * @dev More minimal implementation of Zodiac's Module.sol without an owner
 *      and using unstructured storage
 */
abstract contract ZodiacModule is IZodiacModule, SafeAware {
    struct ZodiacState {
        IAvatar target;
        IGuard guard;
    }

    // ZODIAC_STATE_SLOT = bytes32(uint256(keccak256("firm.zodiacmodule.state")) - 2)
    bytes32 internal constant ZODIAC_STATE_SLOT =
        0x1bcb284404f22ead428604605be8470a4a8a14c8422630d8a717460f9331147d;

    /// @dev Sets the target to a new target (`newTarget`).
    /// @notice Can only be called by the avatar
    function setTarget(IAvatar _target) public onlySafe {
        ZodiacState storage state = zodiacState();
        IAvatar previousTarget = state.target;
        state.target = _target;
        emit TargetSet(previousTarget, _target);
    }

    /// @dev Set a guard that checks transactions before execution.
    /// @param _guard The address of the guard to be used or the 0 address to disable the guard.
    function setGuard(IGuard _guard) external onlySafe {
        if (address(_guard) != address(0)) {
            bytes4 iface = type(IGuard).interfaceId;
            if (!BaseGuard(address(_guard)).supportsInterface(iface))
                revert NotIERC165Compliant(address(_guard));
        }
        zodiacState().guard = _guard;
        emit ChangedGuard(address(_guard));
    }

    /// @dev Passes a transaction to be executed by the avatar.
    /// @notice Can only be called by this contract.
    /// @param to Destination address of module transaction.
    /// @param value Ether value of module transaction.
    /// @param data Data payload of module transaction.
    /// @param operation Operation type of module transaction: 0 == call, 1 == delegate call.
    function exec(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) internal returns (bool success) {
        IGuard guard_ = guard();

        /// Check if a transactioon guard is enabled.
        if (address(guard_) != address(0)) {
            guard_.checkTransaction(
                /// Transaction info used by module transactions.
                to,
                value,
                data,
                operation,
                /// Zero out the redundant transaction information only used for Safe multisig transctions.
                0,
                0,
                0,
                address(0),
                payable(0),
                bytes("0x"),
                msg.sender
            );
        }

        success = target().execTransactionFromModule(
            to,
            value,
            data,
            operation
        );

        if (address(guard_) != address(0)) {
            guard_.checkAfterExecution(bytes32("0x"), success);
        }
    }

    /// @dev Passes a transaction to be executed by the target and returns data.
    /// @notice Can only be called by this contract.
    /// @param to Destination address of module transaction.
    /// @param value Ether value of module transaction.
    /// @param data Data payload of module transaction.
    /// @param operation Operation type of module transaction: 0 == call, 1 == delegate call.
    function execAndReturnData(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) internal returns (bool success, bytes memory returnData) {
        IGuard guard_ = guard();

        /// Check if a transaction guard is enabled.
        if (address(guard_) != address(0)) {
            guard_.checkTransaction(
                /// Transaction info used by module transactions.
                to,
                value,
                data,
                operation,
                /// Zero out the redundant transaction information only used for Safe multisig transctions.
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

        if (address(guard_) != address(0)) {
            guard_.checkAfterExecution(bytes32("0x"), success);
        }
    }

    function avatar() public view override returns (IAvatar) {
        return safe();
    }

    function target() public view override returns (IAvatar) {
        IAvatar target_ = zodiacState().target;
        return address(target_) == address(0) ? safe() : target_;
    }

    function guard() public view override returns (IGuard) {
        return zodiacState().guard;
    }

    function zodiacState() internal pure returns (ZodiacState storage state) {
        assembly {
            state.slot := ZODIAC_STATE_SLOT
        }
    }
}
