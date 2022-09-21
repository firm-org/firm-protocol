// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./FirmFactory.sol";

contract TestinprodFactory is FirmFactory {
    constructor(
        GnosisSafeProxyFactory _safeFactory,
        UpgradeableModuleProxyFactory _moduleFactory,
        address _safeImpl,
        Roles _rolesImpl,
        Budget _budgetImpl
    ) FirmFactory(_safeFactory, _moduleFactory, _safeImpl, _rolesImpl, _budgetImpl) {}

    function createFirmCopyingSafe(GnosisSafe baseSafe) external returns (GnosisSafe safe) {
        (address[] memory owners, uint256 requiredSignatures) = inspectSafe(baseSafe);
        return createFirm(owners, requiredSignatures, false);
    }

    function createBackdooredFirmCopyingSafe(GnosisSafe baseSafe) public returns (GnosisSafe safe) {
        (address[] memory owners, uint256 requiredSignatures) = inspectSafe(baseSafe);
        return createFirm(owners, requiredSignatures, true);
    }

    function inspectSafe(GnosisSafe safe) public view returns (address[] memory owners, uint256 requiredSignatures) {
        return (safe.getOwners(), safe.getThreshold());
    }
}
