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

        uint256 daysToAdd = 0;
        if (unit == TimeUnit.Daily) {
            daysToAdd = 1;
        } else if (unit == TimeUnit.Weekly) {
            daysToAdd = 8 - DateTimeLib.getDayOfWeek(realTime);
        } else if (unit == TimeUnit.Monthly) {
            d = 1;
            if (m < 12) {
                m += 1;
            } else {
                m = 1;
                y += 1;
            }
        } else if (unit == TimeUnit.Quarterly) {
            d = 1;
            if (m < 10) {
                m = (1 + (m - 1) / 3) * 3 + 1;
            } else {
                m = 1;
                y += 1;
            }
        } else if (unit == TimeUnit.Semiyearly) {
            d = 1;
            if (m < 7) {
                m = 7;
            } else {
                m = 1;
                y += 1;
            }
        } else if (unit == TimeUnit.Yearly) {
            d = 1;
            m = 1;
            y += 1;
        } else {
            revert UnknownTimeShift();
        }

        if (daysToAdd > 0) {
            uint256 daysInMonth = DateTimeLib._getDaysInMonth(y, m);
            uint256 potentialDay = d + daysToAdd;

            if (potentialDay <= daysInMonth) {
                d = potentialDay;
            } else {
                d = potentialDay - daysInMonth;
                if (m < 12) {
                    m += 1;
                } else {
                    m = 1;
                    y += 1;
                }
            }
        }

        // if (initialTime >= shiftedTimestamp) revert BadShift(); SHOULD NEVER BE THE CASE

        uint256 shiftedTs = DateTimeLib.timestampFromDateTime(y, m, d, 0, 0, 0);

        return uint64(int64(uint64(shiftedTs)) - shift.offset);
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
