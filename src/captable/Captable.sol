// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.13;

import {UpgradeableModule} from "../bases/UpgradeableModule.sol";
import {IAvatar} from "../bases/SafeAware.sol";

import {ERC1155, ERC1155TokenReceiver} from "./ERC1155.sol";
import {IBouncer} from "./IBouncer.sol";
import {EmbeddedBouncersLib} from "./EmbeddedBouncersLib.sol";

contract Captable is UpgradeableModule, ERC1155 {
    using EmbeddedBouncersLib for IBouncer;

    string public name;
    string public symbol;

    struct Controls {
        IBouncer bouncer;
        mapping(address => bool) canIssue;
    }

    struct Class {
        string name;
        uint256 authorized;
        Controls controls;
        uint256 issued;
    }
    mapping(uint256 => Class) classes;
    uint256 public classCount;

    Controls public globalControls;

    // TODO: all the events
    // TODO: post initialization param customization (global controls, per class controls)

    constructor(
        IAvatar _safe,
        string memory _name,
        string memory _symbol,
        IBouncer _globalBouncer
    ) {
        initialize(_safe, _name, _symbol, _globalBouncer);
    }

    function initialize(
        IAvatar _safe,
        string memory _name,
        string memory _symbol,
        IBouncer _globalBouncer
    ) public {
        __init_setSafe(_safe);
        name = _name;
        symbol = _symbol;
        globalControls.bouncer = _globalBouncer;
        globalControls.canIssue[address(_safe)] = true;
    }

    function createClass(
        string calldata _name,
        uint256 _authorized,
        IBouncer _bouncer,
        address[] calldata _classIssuers
    ) external onlySafe returns (uint256 classId) {
        unchecked {
            classId = classCount++;
        }
        Class storage class = classes[classId];
        class.name = _name;
        class.authorized = _authorized;
        class.controls.bouncer = _bouncer;
        for (uint256 i = 0; i < _classIssuers.length; i++) {
            class.controls.canIssue[_classIssuers[i]] = true;
        }
    }

    error AuthorizedLowerThanOutstanding(uint256 newAuthorized, uint256 issued);

    function authorize(uint256 _classId, uint256 _newAuthorized)
        public
        onlySafe
    {
        Class storage class = classes[_classId];

        if (_newAuthorized < class.issued)
            revert AuthorizedLowerThanOutstanding(_newAuthorized, class.issued);

        class.authorized = _newAuthorized;
    }

    error UnauthorizedIssuer(uint256 classId, address issuer);
    error IssuanceAboveAuthorized(uint256 newIssued, uint256 authorized);

    function issue(
        uint256 _classId,
        address _to,
        uint256 _amount
    ) public {
        Class storage class = classes[_classId];

        bool canIssue = class.controls.canIssue[msg.sender] ||
            globalControls.canIssue[msg.sender];

        if (!canIssue) revert UnauthorizedIssuer(_classId, msg.sender);

        uint256 newIssued = class.issued + _amount;
        if (newIssued > class.authorized)
            revert IssuanceAboveAuthorized(newIssued, class.authorized);

        class.issued = newIssued;
        _mint(_to, _classId, _amount, "");
    }

    error TransferBlocked(
        IBouncer bouncer,
        address from,
        address to,
        uint256 classId,
        uint256 amount
    );

    function _beforeTransfer(
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) internal view override {
        if (!_checkBouncer(globalControls.bouncer, from, to, id, amount))
            revert TransferBlocked(
                globalControls.bouncer,
                from,
                to,
                id,
                amount
            );
        if (!_checkBouncer(classes[id].controls.bouncer, from, to, id, amount))
            revert TransferBlocked(
                classes[id].controls.bouncer,
                from,
                to,
                id,
                amount
            );
    }

    function _checkBouncer(
        IBouncer bouncer,
        address from,
        address to,
        uint256 classId,
        uint256 amount
    ) internal view returns (bool bouncerAllows) {
        EmbeddedBouncersLib.BouncerType bouncerType = bouncer.bouncerType();

        if (bouncerType == EmbeddedBouncersLib.BouncerType.AllowAll) {
            return true;
        }

        if (bouncerType == EmbeddedBouncersLib.BouncerType.NotEmbedded) {
            try bouncer.isTransferAllowed(from, to, classId, amount) returns (
                bool allow
            ) {
                return allow;
            } catch {
                return false;
            }
        }

        if (bouncerType == EmbeddedBouncersLib.BouncerType.DenyAll) {
            return false;
        }

        if (bouncerType == EmbeddedBouncersLib.BouncerType.AllowClassHolders) {
            return balanceOf[to][classId] > 0;
        }

        if (bouncerType == EmbeddedBouncersLib.BouncerType.AllowAllHolders) {
            uint256 classesLength = classCount;
            for (uint256 i = 0; i < classesLength; i++) {
                if (balanceOf[to][i] > 0) {
                    return true;
                }
            }
            return false;
        }

        assert(false); // covered all cases
    }

    function uri(uint256 id) public view override returns (string memory) {
        return string(abi.encodePacked(symbol, bytes(": "), classes[id].name));
    }
}
