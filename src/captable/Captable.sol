// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {UpgradeableModule} from "../bases/UpgradeableModule.sol";
import {IAvatar} from "../bases/SafeAware.sol";

import {EquityToken} from "./EquityToken.sol";
import {IBouncer} from "./IBouncer.sol";

contract Captable is UpgradeableModule {
    string public name;

    struct Class {
        EquityToken token;
        string name;
        string ticker;
    }

    mapping(uint256 => Class) public classes;
    uint256 public classCount;

    error UnexistentClass(uint256 classId);

    constructor(IAvatar safe_, string memory name_, IBouncer globalBouncer_) {
        initialize(safe_, name_, globalBouncer_);
    }

    function initialize(IAvatar safe_, string memory name_, IBouncer globalBouncer_) public {
        __init_setSafe(safe_);
        name = name_;
        // globalControls.bouncer = _globalBouncer;
        // globalControls.canIssue[address(_safe)] = true;
    }

    function createClass(
        string calldata className,
        string calldata ticker,
        // uint256 _convertsIntoClassId,
        uint256 authorized
    )
        // IBouncer _bouncer,
        // address[] calldata _classIssuers
        external
        onlySafe
        returns (uint256 classId, EquityToken token)
    {   
        unchecked {
            classId = classCount++;
        }

        // Consider using proxies as this is >2m gas
        token = new EquityToken(this, classId, authorized);

        Class storage class = classes[classId];
        class.token = token;
        class.name = className;
        class.ticker = ticker;
    }

    function issue(uint256 classId, address account, uint256 amount) external {
        // TODO: issue controls

        Class storage class = _getClass(classId);

        class.token.mint(account, amount);
    }

    // Reverts if transfer isn't allowed so that the revert reason can bubble up
    // If a state update is necessary, we could return a flag from this function
    // and commit that state after tokens are transferred in a separate call?
    function ensureTransferIsAllowed(uint256 classId, address from, address to, uint256 amount) external view {
        Class storage class = _getClass(classId);
    }

    function nameFor(uint256 classId) public view returns (string memory) {
        return string(abi.encodePacked(name, bytes(": "), _getClass(classId).name));
    }

    function tickerFor(uint256 classId) public view returns (string memory) {
        return _getClass(classId).ticker;
    }

    function _getClass(uint256 classId) internal view returns (Class storage) {
        if (classId >= classCount) {
            revert UnexistentClass(classId);
        }
        return classes[classId];
    }
}
