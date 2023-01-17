// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {TestnetTokenFaucet} from "../src/testnet/TestnetTokenFaucet.sol";

contract TestnetFaucetDeploy is Test {
    function run() public {
        vm.startBroadcast();
        
        TestnetTokenFaucet faucet = new TestnetTokenFaucet();

        faucet.create("USD Coin", "USDC", 6);
        faucet.create("Tether USD", "USDT", 6);
        faucet.create("Euro Coin", "EUROC", 6);
        faucet.create("Dai Stablecoin", "DAI", 18);
        faucet.create("Wrapped BTC", "WBTC", 8);
        faucet.create("Uniswap", "UNI", 18);
        faucet.create("ChainLink Token", "LINK", 18);

        vm.stopBroadcast();
    }
}