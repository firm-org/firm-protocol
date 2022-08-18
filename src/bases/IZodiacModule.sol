// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {IAvatar, Enum as SafeEnums} from "zodiac/interfaces/IAvatar.sol";
import {IGuard} from "zodiac/interfaces/IGuard.sol";

abstract contract IZodiacModule {
    event TargetSet(IAvatar indexed previousTarget, IAvatar indexed newTarget);
    event ChangedGuard(address guard);

    error NotIERC165Compliant(address guard_);

    function avatar() public view virtual returns (IAvatar);

    function target() public view virtual returns (IAvatar);

    function guard() public view virtual returns (IGuard);
}
