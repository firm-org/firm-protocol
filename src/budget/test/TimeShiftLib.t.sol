// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "solmate/test/utils/DSTestPlus.sol";
import {BokkyPooBahsDateTimeLibrary as DateTimeLib} from "datetime/BokkyPooBahsDateTimeLibrary.sol";

import "../TimeShiftLib.sol";

contract TimeShiftLibShiftTest is DSTestPlus {
    using TimeShiftLib for *;

    function testDaily() public {
        assertShift(TimeShiftLib.TimeUnit.Daily, 2022, 1, 1, 2022, 1, 2);
        assertShift(TimeShiftLib.TimeUnit.Daily, 2022, 1, 31, 2022, 2, 1);
        assertShift(TimeShiftLib.TimeUnit.Daily, 2022, 2, 28, 2022, 3, 1);
        assertShift(TimeShiftLib.TimeUnit.Daily, 2020, 2, 28, 2020, 2, 29);
        assertShift(TimeShiftLib.TimeUnit.Daily, 2021, 12, 31, 2022, 1, 1);
    }

    function testWeekly() public {
        assertShift(TimeShiftLib.TimeUnit.Weekly, 2022, 1, 1, 2022, 1, 3);
        assertShift(TimeShiftLib.TimeUnit.Weekly, 2022, 1, 31, 2022, 2, 7);
        assertShift(TimeShiftLib.TimeUnit.Weekly, 2021, 12, 28, 2022, 1, 3);
    }

    function testMonthly() public {
        assertShift(TimeShiftLib.TimeUnit.Monthly, 2022, 1, 1, 2022, 2, 1);
        assertShift(TimeShiftLib.TimeUnit.Monthly, 2022, 1, 31, 2022, 2, 1);
        assertShift(TimeShiftLib.TimeUnit.Monthly, 2022, 12, 3, 2023, 1, 1);
    }

    function testQuarterly() public {
        assertShift(TimeShiftLib.TimeUnit.Quarterly, 2022, 1, 1, 2022, 4, 1);
        assertShift(TimeShiftLib.TimeUnit.Quarterly, 2022, 1, 31, 2022, 4, 1);
        assertShift(TimeShiftLib.TimeUnit.Quarterly, 2022, 4, 3, 2022, 7, 1);
        assertShift(TimeShiftLib.TimeUnit.Quarterly, 2022, 5, 3, 2022, 7, 1);
        assertShift(TimeShiftLib.TimeUnit.Quarterly, 2022, 6, 3, 2022, 7, 1);
        assertShift(TimeShiftLib.TimeUnit.Quarterly, 2022, 10, 3, 2023, 1, 1);
    }

    function testSemiyearly() public {
        assertShift(TimeShiftLib.TimeUnit.Semiyearly, 2022, 1, 1, 2022, 7, 1);
        assertShift(TimeShiftLib.TimeUnit.Semiyearly, 2022, 1, 31, 2022, 7, 1);
        assertShift(TimeShiftLib.TimeUnit.Semiyearly, 2022, 6, 3, 2022, 7, 1);
        assertShift(TimeShiftLib.TimeUnit.Semiyearly, 2022, 7, 3, 2023, 1, 1);
        assertShift(TimeShiftLib.TimeUnit.Semiyearly, 2022, 8, 3, 2023, 1, 1);
        assertShift(TimeShiftLib.TimeUnit.Semiyearly, 2022, 12, 3, 2023, 1, 1);
    }

    function testYearly() public {
        assertShift(TimeShiftLib.TimeUnit.Yearly, 2022, 1, 1, 2023, 1, 1);
        assertShift(TimeShiftLib.TimeUnit.Yearly, 2022, 1, 31, 2023, 1, 1);
    }

    function testOffsets() public {
        TimeShiftLib.TimeShift memory shift = TimeShiftLib.TimeShift(TimeShiftLib.TimeUnit.Monthly, 1 hours);

        assertEq(
            uint64(DateTimeLib.timestampFromDateTime(2022, 1, 1, 23, 23, 0))
                .applyShift(shift),
            DateTimeLib.timestampFromDateTime(2022, 1, 31, 23, 0, 0)
        );
        assertEq(
            uint64(DateTimeLib.timestampFromDateTime(2022, 1, 31, 23, 23, 0))
                .applyShift(shift),
            DateTimeLib.timestampFromDateTime(2022, 2, 28, 23, 0, 0)
        );
    }

    uint64 immutable from_ = uint64(DateTimeLib.timestampFromDateTime(2022, 12, 28, 0, 0, 0));
    uint64 immutable to_ = uint64(DateTimeLib.timestampFromDateTime(2023, 1, 2, 0, 0, 0));
    function testGasWorstCase() public {
        TimeShiftLib.TimeShift memory shift = TimeShiftLib.TimeShift(TimeShiftLib.TimeUnit.Weekly, 0);

        uint256 initialGas = gasleft();
        assertEq(
            uint64(from_).applyShift(shift),
            to_
        );

        assertLt(initialGas - gasleft(), 12000);
    }
    
    function assertShift(
        TimeShiftLib.TimeUnit unit,
        uint256 y1,
        uint256 m1,
        uint256 d1,
        uint256 y2,
        uint256 m2,
        uint256 d2
    ) public {
        assertEq(
            uint64(DateTimeLib.timestampFromDate(y1, m1, d1)).applyShift(
                TimeShiftLib.TimeShift(unit, 0)
            ),
            DateTimeLib.timestampFromDate(y2, m2, d2)
        );
    }
}

contract TimeShiftLibEncodingTest is DSTestPlus {
    using TimeShiftLib for *;

    function testRoundtrips() public {
        assertRoundtrip(TimeShiftLib.TimeUnit.Daily, 0);
        assertRoundtrip(TimeShiftLib.TimeUnit.Daily, -1);
        assertRoundtrip(TimeShiftLib.TimeUnit.Monthly, -1 hours);
        assertRoundtrip(TimeShiftLib.TimeUnit.Yearly, -1000 * 365 days);
    }

    function testEncodingGas() public {
        TimeShiftLib.TimeShift memory shift = TimeShiftLib.TimeShift(TimeShiftLib.TimeUnit.Monthly, -1 hours);
        assertEq(
            uint256(uint72(EncodedTimeShift.unwrap(shift.encode()))),
            0x02fffffffffffff1f0
        );
    }

    function testDecodingGas() public {
        EncodedTimeShift encodedShift = EncodedTimeShift.wrap(0x02fffffffffffff1f0);

        TimeShiftLib.TimeShift memory decoded = encodedShift.decode();

        assertEq(uint8(decoded.unit), uint8(TimeShiftLib.TimeUnit.Monthly));
        assertEq(decoded.offset, -1 hours);
    }

    function assertRoundtrip(TimeShiftLib.TimeUnit inputUnit, int64 inputOffset) public {
        TimeShiftLib.TimeShift memory shift = TimeShiftLib.TimeShift(inputUnit, inputOffset);
        EncodedTimeShift encoded = shift.encode();
        //emit log_bytes(abi.encodePacked(encoded));
        TimeShiftLib.TimeShift memory decodedEncoded = encoded.decode();

        assertEq(uint8(decodedEncoded.unit), uint8(inputUnit));
        assertEq(decodedEncoded.offset, inputOffset);
    }
}