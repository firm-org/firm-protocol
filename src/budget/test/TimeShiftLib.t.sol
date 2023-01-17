// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {BokkyPooBahsDateTimeLibrary as DateTimeLib} from "datetime/BokkyPooBahsDateTimeLibrary.sol";

import {FirmTest} from "../../bases/test/lib/FirmTest.sol";
import "../TimeShiftLib.sol";

contract TimeShiftLibShiftTest is FirmTest {
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

    function testRevertIfUnitIsInherited() public {
        vm.expectRevert(abi.encodeWithSelector(TimeShiftLib.InvalidTimeShift.selector));
        uint40(block.timestamp).applyShift(TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode());

        vm.expectRevert(abi.encodeWithSelector(TimeShiftLib.InvalidTimeShift.selector));
        uint40(block.timestamp).applyShift(TimeShift(TimeShiftLib.TimeUnit.Inherit, 1).encode());
    }

    function testRevertIfUnitIsNonRecurrent() public {
        vm.expectRevert(abi.encodeWithSelector(TimeShiftLib.InvalidTimeShift.selector));
        uint40(block.timestamp).applyShift(TimeShift(TimeShiftLib.TimeUnit.NonRecurrent, 0).encode());

        vm.expectRevert(abi.encodeWithSelector(TimeShiftLib.InvalidTimeShift.selector));
        uint40(block.timestamp).applyShift(
            TimeShift(TimeShiftLib.TimeUnit.NonRecurrent, int40(uint40(block.timestamp + 1000))).encode()
        );
    }

    function testOffsets() public {
        TimeShift memory shift = TimeShift(TimeShiftLib.TimeUnit.Monthly, 1 hours);

        assertEq(
            uint40(DateTimeLib.timestampFromDateTime(2022, 1, 1, 23, 23, 0)).applyShift(shift.encode()),
            DateTimeLib.timestampFromDateTime(2022, 1, 31, 23, 0, 0)
        );
        assertEq(
            uint40(DateTimeLib.timestampFromDateTime(2022, 1, 31, 23, 23, 0)).applyShift(shift.encode()),
            DateTimeLib.timestampFromDateTime(2022, 2, 28, 23, 0, 0)
        );
    }

    uint40 immutable from_ = uint40(DateTimeLib.timestampFromDateTime(2022, 12, 28, 0, 0, 0));
    uint40 immutable to_ = uint40(DateTimeLib.timestampFromDateTime(2023, 1, 2, 0, 0, 0));

    function testGasWorstCase() public {
        TimeShift memory shift = TimeShift(TimeShiftLib.TimeUnit.Weekly, 0);

        uint256 initialGas = gasleft();
        assertEq(uint40(from_).applyShift(shift.encode()), to_);

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
            uint40(DateTimeLib.timestampFromDate(y1, m1, d1)).applyShift(TimeShift(unit, 0).encode()),
            DateTimeLib.timestampFromDate(y2, m2, d2)
        );
    }
}

contract TimeShiftLibEncodingTest is FirmTest {
    using TimeShiftLib for *;

    function testRoundtrips() public {
        assertRoundtrip(TimeShiftLib.TimeUnit.Daily, 0);
        assertRoundtrip(TimeShiftLib.TimeUnit.Daily, -1);
        assertRoundtrip(TimeShiftLib.TimeUnit.Monthly, -1 hours);
        assertRoundtrip(TimeShiftLib.TimeUnit.Yearly, -1000 * 365 days);
    }

    function testEncodingGas() public {
        TimeShift memory shift = TimeShift(TimeShiftLib.TimeUnit.Monthly, -1 hours);
        assertEq(uint256(uint48(EncodedTimeShift.unwrap(shift.encode()))), 0x03fffffff1f0);
    }

    function testDecodingGas() public {
        EncodedTimeShift encodedShift = EncodedTimeShift.wrap(0x03fffffff1f0);

        (TimeShiftLib.TimeUnit unit, int40 offset) = encodedShift.decode();

        assertEq(uint8(unit), uint8(TimeShiftLib.TimeUnit.Monthly));
        assertEq(offset, -1 hours);
    }

    function assertRoundtrip(TimeShiftLib.TimeUnit inputUnit, int40 inputOffset) public {
        TimeShift memory shift = TimeShift(inputUnit, inputOffset);
        EncodedTimeShift encoded = shift.encode();
        (TimeShiftLib.TimeUnit unit, int40 offset) = encoded.decode();

        assertEq(uint8(unit), uint8(inputUnit));
        assertEq(offset, inputOffset);
    }
}

contract TimeShiftLibHelpersTest is FirmTest {
    using TimeShiftLib for *;

    function testIsInherited() public {
        assertTrue(TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode().isInherited());
        assertTrue(TimeShift(TimeShiftLib.TimeUnit.Inherit, 1).encode().isInherited());
        assertFalse(TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode().isInherited());
    }

    function testIsNonRecurrent() public {
        assertTrue(TimeShift(TimeShiftLib.TimeUnit.NonRecurrent, 0).encode().isNonRecurrent());
        assertTrue(
            TimeShift(TimeShiftLib.TimeUnit.NonRecurrent, int40(uint40(block.timestamp))).encode().isNonRecurrent()
        );
        assertFalse(TimeShift(TimeShiftLib.TimeUnit.Yearly, type(int40).max).encode().isNonRecurrent());
    }
}
