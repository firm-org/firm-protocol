// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {RolesAuth, IRoles} from "../../RolesAuth.sol";

contract RolesAuthMock is RolesAuth {
    constructor(IRoles _roles) {
        _setRoles(_roles);
    }

    function isAuthorized(address _sender, address _authorized) public view returns (bool) {
        return _isAuthorized(_sender, _authorized);
    }
}
