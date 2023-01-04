// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../../FirmRolesAuth.sol";

function roleFlag(uint8 role) pure returns (address) {
    return AddressUint8FlagsLib.toFlag(role, ROLES_FLAG_TYPE);
}

contract RolesAuthMock is FirmRolesAuth {
    constructor(IRoles _roles) {
        _setRoles(_roles);
    }

    function isAuthorized(address _sender, address _authorized) public view returns (bool) {
        return _isAuthorized(_sender, _authorized);
    }
}
