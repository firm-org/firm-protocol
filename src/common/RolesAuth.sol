// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {IRoles} from "../roles/IRoles.sol";

abstract contract RolesAuth {
    IRoles public roles;

    uint256 private constant ROLE_FLAG_MASK = ~uint160(0xFF00);

    function _isAuthorized(address _actor, address _authorizedAddr)
        internal
        view
        returns (bool)
    {
        if (_actor == _authorizedAddr) return true;

        // An address 0x00...00[roleId byte]01 is interpreted as a flag for roleId
        // Eg. 0x0000000000000000000000000000000000000201 for roleId=2
        uint160 flag = uint160(_authorizedAddr);
        return
            flag & ROLE_FLAG_MASK == 0x01 &&
            roles.hasRole(_actor, uint8(flag >> 8));
    }
}
