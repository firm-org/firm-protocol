// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {SafeAware} from "./SafeAware.sol";

abstract contract UpgradeableModule is SafeAware {
    event Upgraded(address indexed implementation);

    // EIP1967_IMPL_SLOT = bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)
    bytes32 internal constant EIP1967_IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice Upgrades the proxy to a new implementation address
    /// @dev The new implementation should be a contract that implements a way to perform upgrades as well
    ////     otherwise the proxy will freeze on that implementation forever, since the proxy doesn't contain logic to change it.
    /// @param _newImplementation The address of the new implementation address the proxy will use
    function upgrade(address _newImplementation) public onlySafe {
        assembly {
            sstore(EIP1967_IMPL_SLOT, _newImplementation)
        }

        emit Upgraded(_newImplementation);
    }
}
