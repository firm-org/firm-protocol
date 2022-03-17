// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "zodiac/interfaces/IAvatar.sol";
import "zodiac/interfaces/IGuard.sol";
import "zodiac/guard/BaseGuard.sol";

/**
 * @title FirmModule
 * @dev More minimal implementation of Zodiac's Module.sol without an owner
 *      and using unstructured storage
 */
abstract contract FirmModule {
    struct ModuleState {
        IAvatar avatar;
        IAvatar target;
        IGuard guard;
    }
    
    // Same events as Zodiac for compatibility
    event AvatarSet(IAvatar indexed previousAvatar, IAvatar indexed newAvatar);
    event TargetSet(IAvatar indexed previousTarget, IAvatar indexed newTarget);
    event ChangedGuard(address guard);

    error AlreadyInitialized();
    error UnauthorizedNotAvatar();
    error NotIERC165Compliant(address guard_);

    modifier onlyAvatar {
        if (address(moduleState().avatar) != msg.sender) {
            revert UnauthorizedNotAvatar();
        }
        _;
    }

    function initialize(IAvatar _avatar, IAvatar _target) public virtual {
        ModuleState storage state = moduleState();

        if (address(state.avatar) != address(0)) {
            revert AlreadyInitialized();
        }

        state.avatar = _avatar;
        state.target = _target;
    }

    /// @dev Sets the avatar to a new avatar (`newAvatar`).
    /// @notice Can only be called by the current avatar
    function setAvatar(IAvatar _avatar) public onlyAvatar {
        ModuleState storage state = moduleState();
        IAvatar previousAvatar = state.avatar;
        state.avatar = _avatar;
        emit AvatarSet(previousAvatar, _avatar);
    }

    /// @dev Sets the target to a new target (`newTarget`).
    /// @notice Can only be called by the avatar
    function setTarget(IAvatar _target) public onlyAvatar {
        ModuleState storage state = moduleState();
        IAvatar previousTarget = state.target;
        state.target = _target;
        emit TargetSet(previousTarget, _target);
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
        ModuleState storage state = moduleState();
        IGuard guard_ = state.guard;

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

        success = state.target.execTransactionFromModule(to, value, data, operation);

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
        ModuleState storage state = moduleState();
        IGuard guard_ = state.guard;

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

        (success, returnData) = state.target
            .execTransactionFromModuleReturnData(to, value, data, operation);

        if (address(guard_) != address(0)) {
            guard_.checkAfterExecution(bytes32("0x"), success);
        }
    }

    /// @dev Set a guard that checks transactions before execution.
    /// @param _guard The address of the guard to be used or the 0 address to disable the guard.
    function setGuard(IGuard _guard) external onlyAvatar {
        if (address(_guard) != address(0)) {
            if (!BaseGuard(address(_guard)).supportsInterface(type(IGuard).interfaceId))
                revert NotIERC165Compliant(address(_guard));
        }
        moduleState().guard = _guard;
        emit ChangedGuard(address(_guard));
    }

    function avatar() public view returns (IAvatar) {
        return moduleState().avatar;
    }

    function target() public view returns (IAvatar) {
        return moduleState().target;
    }

    function guard() public view returns (IGuard) {
        return moduleState().guard;
    }

    // MODULE_STATE_SLOT = bytes32(uint256(keccak256("firm.module.state")) - 3)
    bytes32 internal constant MODULE_STATE_SLOT = 0xa5b7510e75e06df92f176662510e3347b687605108b9f72b4260aa7cf56ebb12;
    function moduleState() internal pure returns (ModuleState storage state) {
        assembly {
            state.slot := MODULE_STATE_SLOT
        }
    }
}