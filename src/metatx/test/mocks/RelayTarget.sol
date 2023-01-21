// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {ERC2771Context} from "../../../bases/ERC2771Context.sol";

contract RelayTarget is ERC2771Context {
    error BadSender(address expected, address actual);

    address public lastSender;

    constructor(address trustedForwarder) {
        _setTrustedForwarder(trustedForwarder, true);
    }

    function onlySender(address expectedSender) public returns (address sender) {
        sender = _msgSender();

        if (sender != expectedSender) {
            revert BadSender(expectedSender, _msgSender());
        }

        lastSender = sender;
    }
}
