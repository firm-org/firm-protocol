// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

// As of FiatTokenV2_1 impl
// https://etherscan.io/address/0xa2327a938febf5fec13bacfb16ae10ecbc4cbdcf#code
interface IUSDCMinting {
    function masterMinter() external view returns (address);
    function configureMinter(address minter, uint256 minterAllowedAmount) external returns (bool);
}
