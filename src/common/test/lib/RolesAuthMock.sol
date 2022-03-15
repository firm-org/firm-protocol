// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../RolesAuth.sol";

contract RolesAuthMock is RolesAuth {
    constructor(IRoles _roles) {
        roles = _roles;
    }

    function isAuthorized(address _sender, address _authorized) public view returns (bool) {
        return _isAuthorized(_sender, _authorized);
    }    
}