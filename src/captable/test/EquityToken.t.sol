// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";

import {Captable} from "../Captable.sol";
import {EquityToken} from "../EquityToken.sol";

contract EquityTokenTest is FirmTest {
    Captable captable;

    /*
    function setUp() public {
        captable = new Captable();
    }
    */

    function testGasDeploy() public {
        new EquityToken(Captable(address(0)), 0);
    }
}
