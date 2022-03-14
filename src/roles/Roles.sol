// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

/*
    Inspired by Solmate's RolesAuthority (https://github.com/Rari-Capital/solmate/blob/main/src/auth/authorities/RolesAuthority.sol)
    and OpenZeppelin's AccessControl (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol)

    Supports up to 256 roles
*/

uint8 constant ROOT_ROLE = 0;
bytes32 constant ROOT_AS_ADMIN = bytes32(uint256(1));

contract Roles {
    mapping (address => bytes32) public getUserRoles;
    mapping (uint8 => bytes32) public getRoleAdmin;
    uint256 public roleCount;

    event RoleCreated(uint8 indexed roleId, bytes32 roleAdmin, string name);
    event RolesSet(address indexed user, bytes32 userRoles, address indexed actor);
    
    error UnauthorizedNoRole(uint8 requiredRole);
    error UnauthorizedNotAdmin(uint8 role);
    error RoleLimitReached();

    constructor(address _initialAdmin) {
        _createRole(ROOT_AS_ADMIN, "Root role");
        getUserRoles[_initialAdmin] = bytes32(uint256(1)); // Admin just gets root role. Should it get all the roles?
    }

    function createRole(bytes32 roleAdmin, string memory _name) public returns (uint8 roleId) {
        if (!hasRole(msg.sender, ROOT_ROLE)) revert UnauthorizedNoRole(ROOT_ROLE);
        return _createRole(roleAdmin, _name);
    }

    function _createRole(bytes32 _roleAdmin, string memory _name) internal returns (uint8 roleId) {
        uint256 roleCount_ = roleCount;
        if (roleCount_ == 256) revert RoleLimitReached();
         unchecked {
            roleCount = roleCount_ + 1;
        }

        roleId = uint8(roleCount_);
        getRoleAdmin[roleId] = _roleAdmin;

        emit RoleCreated(roleId, _roleAdmin, _name);
    }

    function setRole(address _user, uint8 _role, bool _grant) public {
        bytes32 userRoles = getUserRoles[_user];

        if (!_isRoleAdmin(getUserRoles[msg.sender], _role)) revert UnauthorizedNotAdmin(_role);

        if (_grant) {
            userRoles |= bytes32(1 << _role);
        } else {
            userRoles &= ~bytes32(1 << _role);
        }

        getUserRoles[_user] = userRoles;

        emit RolesSet(_user, userRoles, msg.sender);
    }

    function setRoles(address _user, uint8[] memory _grantingRoles, uint8[] memory _revokingRoles) public {
        bytes32 senderRoles = getUserRoles[msg.sender];
        bytes32 userRoles = getUserRoles[_user];

        uint256 grantsLength = _grantingRoles.length;
        for (uint256 i = 0; i < grantsLength; i++) {
            uint8 role = _grantingRoles[i];
            if (!_isRoleAdmin(senderRoles, role)) revert UnauthorizedNotAdmin(role);

            userRoles |= bytes32(1 << role); 
        }

        uint256 revokesLength = _revokingRoles.length;
        for (uint256 i = 0; i < revokesLength; i++) {
            uint8 role = _revokingRoles[i];
            if (!_isRoleAdmin(senderRoles, role)) revert UnauthorizedNotAdmin(role);

            userRoles &= ~(bytes32(1 << role));
        }

        getUserRoles[_user] = userRoles;

        emit RolesSet(_user, userRoles, msg.sender);
    }

    function hasRole(address _user, uint8 _roleId) public view returns (bool) {
        // TODO: Should role admins automatically have the role as well?
        return uint256(getUserRoles[_user] >> _roleId) & 1 != 0;
    }

    function isRoleAdmin(address _user, uint8 _roleId) public view returns (bool) {
        return _isRoleAdmin(getUserRoles[_user], _roleId);
    }

    function _isRoleAdmin(bytes32 _userRoles, uint8 _roleId) internal view returns (bool) {
        return _userRoles & getRoleAdmin[_roleId] != 0;
    }
}