// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

// Formal verification for library and formula: https://twitter.com/Zellic_io/status/1510341868021854209
import {BokkyPooBahsDateTimeLibrary as DateTimeLib} from "datetime/BokkyPooBahsDateTimeLibrary.sol";

type EncodedTimeShift is bytes6;

struct TimeShift {
    TimeShiftLib.TimeUnit unit; // in the special case of seconds, offset doesn't apply
    int40 offset;
}

function encode(TimeShift memory shift) pure returns (EncodedTimeShift) {
    return EncodedTimeShift.wrap(bytes6(abi.encodePacked(uint8(shift.unit), shift.offset)));
}

function decode(EncodedTimeShift encoded) pure returns (TimeShiftLib.TimeUnit unit, int40 offset) {
    uint48 encodedValue = uint48(EncodedTimeShift.unwrap(encoded));
    unit = TimeShiftLib.TimeUnit(uint8(encodedValue >> 40));
    offset = int40(uint40(uint48(encodedValue)));
}

function isInherited(EncodedTimeShift encoded) pure returns (bool) {
    return EncodedTimeShift.unwrap(encoded) == bytes6(0);
}

using {decode, isInherited} for EncodedTimeShift global;
using {encode} for TimeShift global;

library TimeShiftLib {
    using TimeShiftLib for *;

    enum TimeUnit {
        Inherit,
        Daily,      // 1
        Weekly,     // 2
        Monthly,    // 3
        Quarterly,  // 4
        Semiyearly, // 5
        Yearly      // 6
    }

    error InvalidTimeShift();

    function applyShift(uint40 time, EncodedTimeShift shift) internal pure returns (uint40) {
        (TimeUnit unit, int40 offset) = shift.decode();

        uint40 realTime = uint40(int40(time) + offset);
        (uint256 y, uint256 m, uint256 d) = realTime.toDate();

        // Split branches for shorter paths and put the most common cases first
        if (uint8(unit) > 3) {
            if (unit == TimeUnit.Yearly) {
                (y, m, d) = (y + 1, 1, 1);
            } else if (unit == TimeUnit.Quarterly) {
                (y, m, d) = m < 10 ? (y, (1 + (m - 1) / 3) * 3 + 1, 1) : (y + 1, 1, 1);
            } else if (unit == TimeUnit.Semiyearly) {
                (y, m, d) = m < 7 ? (y, 7, 1) : (y + 1, 1, 1);
            } else {
                revert InvalidTimeShift();
            }
        } else {
            if (unit == TimeUnit.Monthly) {
                (y, m, d) = m < 12 ? (y, m + 1, 1) : (y + 1, 1, 1);
            } else if (unit == TimeUnit.Weekly) {
                (y, m, d) = addDays(y, m, d, 8 - DateTimeLib.getDayOfWeek(realTime));
            } else if (unit == TimeUnit.Daily) {
                (y, m, d) = addDays(y, m, d, 1);
            } else {
                revert InvalidTimeShift();
            }
        }

        uint256 shiftedTs = DateTimeLib.timestampFromDateTime(y, m, d, 0, 0, 0);
        return uint40(int40(uint40(shiftedTs)) - offset);
    }

    /**
     * @dev IT WILL ONLY TRANSITION ONE MONTH IF NECESSARY
     */
    function addDays(uint256 y, uint256 m, uint256 d, uint256 daysToAdd)
        private
        pure
        returns (uint256, uint256, uint256)
    {
        uint256 daysInMonth = DateTimeLib._getDaysInMonth(y, m);
        uint256 d2 = d + daysToAdd;

        return d2 <= daysInMonth ? (y, m, d2) : m < 12 ? (y, m + 1, d2 - daysInMonth) : (y + 1, 1, d2 - daysInMonth);
    }

    function toDate(uint40 timestamp) internal pure returns (uint256 y, uint256 m, uint256 d) {
        return DateTimeLib._daysToDate(timestamp / 1 days);
    }
}
