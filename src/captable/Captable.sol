// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.13;

import {ERC1155, ERC1155TokenReceiver} from "./ERC1155.sol";

contract Captable is ERC1155 {
    string public name;
    string public symbol;

    struct Class {
        string name;
        uint256 authorized;
        uint256 issued;
    }
    mapping(uint256 => Class) public classes;
    uint256 classCount;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function createClass(string memory _name, uint256 _authorized) public {
        uint256 classId;
        unchecked {
            classId = classCount++;
        }
        Class storage class = classes[classId];
        class.name = _name;
        class.authorized = _authorized;
    }

    error AuthorizedLowerThanOutstanding(uint256 newAuthorized, uint256 issued);

    function authorizeShares(uint256 _id, uint256 _newAuthorized) public {
        Class storage class = classes[_id];

        if (_newAuthorized < class.issued) {
            revert AuthorizedLowerThanOutstanding(_newAuthorized, class.issued);
        }

        class.authorized = _newAuthorized;
    }

    error IssuanceAboveAuthorized(uint256 newIssued, uint256 authorized);

    function issue(
        uint256 _id,
        address _to,
        uint256 _amount
    ) public {
        Class storage class = classes[_id];

        uint256 newIssued = class.issued + _amount;
        if (newIssued > class.authorized) {
            revert IssuanceAboveAuthorized(newIssued, class.authorized);
        }

        class.issued = newIssued;
        _mint(_to, _id, _amount, "");
    }

    function _beforeTransfer(
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) internal override {
        // Revert to prevent transfers
    }

    function uri(uint256 id) public view override returns (string memory) {
        return string(abi.encodePacked(symbol, bytes(":"), classes[id].name));
    }
}
