// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "zodiac/interfaces/IAvatar.sol";

abstract contract SafeAware {
    // bytes32 internal constant SAFE_SLOT = bytes32(uint256(keccak256("firm.safeaware.safe")) - 1);
    bytes32 internal constant SAFE_SLOT =
        0xb2c095c1a3cccf4bf97d6c0d6a44ba97fddb514f560087d9bf71be2c324b6c44;

    error SafeAddressZero();
    error AlreadyInitialized();
    error UnauthorizedNotSafe();

    modifier onlySafe() {
        if (msg.sender != address(safe())) revert UnauthorizedNotSafe();

        _;
    }

    function __init_setSafe(IAvatar _safe) internal {
        if (address(_safe) == address(0)) revert SafeAddressZero();
        if (address(safe()) != address(0)) revert AlreadyInitialized();
        assembly {
            sstore(SAFE_SLOT, _safe)
        }
    }

    function safe() public view returns (IAvatar safeAddr) {
        assembly {
            safeAddr := sload(SAFE_SLOT)
        }
    }
}
