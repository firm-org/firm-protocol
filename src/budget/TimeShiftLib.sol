// SPDX-License-Identifier: UNLICENSED

import {BokkyPooBahsDateTimeLibrary as DateTimeLib} from "datetime/BokkyPooBahsDateTimeLibrary.sol";

pragma solidity 0.8.10;

library TimeShiftLib {
    using TimeShiftLib for *;

    enum TimeUnit {
        Daily,
        Weekly,
        Monthly,
        Quarterly,
        Semiyearly,
        Yearly
    }

    struct TimeShift {
        TimeUnit unit; // in the special case of seconds, offset doesn't apply
        int64 offset;
    }

    // TODO: Could add a special 'Seconds' time unit which would just apply the offset directly
    //       Eg. TimeShift(Seconds, 100) would shift in 100 second intervals (would have to take into account the last time it was reset)

    error UnknownTimeShift();
    error BadShift();

    function applyShift(uint64 time, TimeShift memory shift)
        internal
        pure
        returns (uint64)
    {
        uint64 realTime = uint64(int64(time) + shift.offset);
        (uint256 y, uint256 m, uint256 d) = realTime.toDate();
        TimeUnit unit = shift.unit;

        if (unit == TimeUnit.Daily) {
            (y, m, d) = addDays(y, m, d, 1);
        } else if (unit == TimeUnit.Weekly) {
            (y, m, d) = addDays(y, m, d, 8 - DateTimeLib.getDayOfWeek(realTime));
        } else if (unit == TimeUnit.Monthly) {
            (y, m, d) = m < 12 ? (y, m + 1, 1) : (y + 1, 1, 1);
        } else if (unit == TimeUnit.Quarterly) {
            (y, m, d) = m < 10 ? (y, (1 + (m - 1) / 3) * 3 + 1, 1) : (y + 1, 1, 1);
        } else if (unit == TimeUnit.Semiyearly) {
            (y, m, d) = m < 7 ? (y, 7, 1) : (y + 1, 1, 1);
        } else if (unit == TimeUnit.Yearly) {
            (y, m, d) = (y + 1, 1, 1);
        } else {
            revert UnknownTimeShift();
        }

        uint256 shiftedTs = DateTimeLib.timestampFromDateTime(y, m, d, 0, 0, 0);
        return uint64(int64(uint64(shiftedTs)) - shift.offset);
    }

    /**
     * @dev IT WILL ONLY TRANSITION ONE MONTH IF NECESSARY
     */
    function addDays(uint256 y, uint256 m, uint256 d, uint256 daysToAdd) private pure returns (uint256, uint256, uint256) {
        uint256 daysInMonth = DateTimeLib._getDaysInMonth(y, m);
        uint256 d2 = d + daysToAdd;

        return d2 <= daysInMonth
            ? (y, m, d2)
            : m < 12
                ? (y, m + 1, d2 - daysInMonth)
                : (y + 1, 1, d2 - daysInMonth);
    }

    function toDate(uint64 timestamp)
        internal
        pure
        returns (
            uint256 y,
            uint256 m,
            uint256 d
        )
    {
        return DateTimeLib._daysToDate(timestamp / 1 days);
    }
}
