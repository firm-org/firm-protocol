// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {ERC20, ERC20Votes, ERC20Permit} from "openzeppelin/token/ERC20/extensions/ERC20Votes.sol";

import {Captable} from "./Captable.sol";

// NOTE: without a proxy just the vanilla erc20votes costs +1.5m gas
// TODO: consider whether using proxies is worth it for equity tokens
contract EquityToken is ERC20Votes {
    Captable public immutable captable;
    uint256 public immutable classId;

    uint256 public authorized;

    error UnauthorizedNotCaptable();
    error IssuingOverAuthorized();

    modifier onlyCaptable() {
        if (msg.sender != address(captable)) {
            revert UnauthorizedNotCaptable();
        }

        _;
    }

    constructor(Captable captable_, uint256 classId_, uint256 authorized_) ERC20("", "") ERC20Permit("") {
        captable = captable_;
        classId = classId_;
        authorized = authorized_;
    }

    function mint(address account, uint256 amount) external onlyCaptable {
        if (totalSupply() + amount > authorized) {
            revert IssuingOverAuthorized();
        }

        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external onlyCaptable {
        _burn(account, amount);
    }

    function forfeit(address from, address to, uint256 amount) external onlyCaptable {
        _transfer(from, to, amount);
        // TODO: emit event since Forfeit is otherwise undetectable from observing events
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // Transfers triggered by Captable are always allowed and not checked
        if (msg.sender != address(captable)) {
            captable.ensureTransferIsAllowed(from, to, classId, amount);
        }
        
        super._beforeTokenTransfer(from, to, amount);
    }

    function name() public view override returns (string memory) {
        return captable.nameFor(classId);
    }

    function symbol() public view override returns (string memory) {
        return captable.tickerFor(classId);
    }
}
