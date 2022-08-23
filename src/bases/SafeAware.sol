// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {IAvatar} from "zodiac/interfaces/IAvatar.sol";

/**
 * @title SafeAware
 * @dev Base contract for Firm components that need to be aware of a Safe
 * as their admin
 */
abstract contract SafeAware {
    // SAFE_SLOT = keccak256("firm.safeaware.safe") - 1
    bytes32 internal constant SAFE_SLOT = 0xb2c095c1a3cccf4bf97d6c0d6a44ba97fddb514f560087d9bf71be2c324b6c44;

    /**
     * @notice Address of the Safe that this module is tied to
     */
    function safe() public view returns (IAvatar safeAddr) {
        assembly {
            safeAddr := sload(SAFE_SLOT)
        }
    }

    error SafeAddressZero();
    error AlreadyInitialized();

    event FirmModuleInit(address indexed safe, bytes32 indexed moduleId, uint256 moduleVersion);

    function moduleId() internal pure virtual returns (bytes32);
    function moduleVersion() internal pure virtual returns (uint256);

    /**
     * @dev Contracts that inherit from SafeAware, including derived contracts as
     * UpgradeableModule or Zodiac, should call this function on initialization
     * Will revert if called twice
     * @param _safe The address of the GnosisSafe to use, won't be modifiable unless
     * implicitly implemented by the derived contract, which is not recommended
     */
    function __init_setSafe(IAvatar _safe) internal {
        if (address(_safe) == address(0)) {
            revert SafeAddressZero();
        }
        if (address(safe()) != address(0)) {
            revert AlreadyInitialized();
        }
        assembly {
            sstore(SAFE_SLOT, _safe)
        }

        emit FirmModuleInit(address(_safe), moduleId(), moduleVersion());
    }

    error UnauthorizedNotSafe();
    /**
     * @dev Modifier to be used by derived contracts to limit access control to priviledged
     * functions so they can only be called by the Safe
     */

    modifier onlySafe() {
        if (msg.sender != address(safe())) {
            revert UnauthorizedNotSafe();
        }

        _;
    }
}