// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./FirmFactory.sol";

contract TestinprodFactory is FirmFactory {
    constructor(
        GnosisSafeProxyFactory _safeFactory,
        UpgradeableModuleProxyFactory _moduleFactory,
        FirmRelayer _relayer,
        address _safeImpl
    ) FirmFactory(_safeFactory, _moduleFactory, _relayer, _safeImpl) {}

    function createFirmCopyingSafe(GnosisSafe baseSafe, uint256 nonce) external returns (GnosisSafe safe) {
        (address[] memory owners, uint256 requiredSignatures) = inspectSafe(baseSafe);
        return createFirm(owners, requiredSignatures, false, nonce);
    }

    function createBackdooredFirmCopyingSafe(GnosisSafe baseSafe, uint256 nonce) public returns (GnosisSafe safe) {
        (address[] memory owners, uint256 requiredSignatures) = inspectSafe(baseSafe);
        return createFirm(owners, requiredSignatures, true, nonce);
    }

    function inspectSafe(GnosisSafe safe) public view returns (address[] memory owners, uint256 requiredSignatures) {
        return (safe.getOwners(), safe.getThreshold());
    }
}
