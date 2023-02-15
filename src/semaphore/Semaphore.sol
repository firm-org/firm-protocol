// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {BaseGuard, Enum} from "safe/base/GuardManager.sol";

import {FirmBase, ISafe, IMPL_INIT_NOOP_ADDR, IMPL_INIT_NOOP_SAFE} from "../bases/FirmBase.sol";

contract Semaphore is FirmBase, BaseGuard {
    string public constant moduleId = "org.firm.semaphore";
    uint256 public constant moduleVersion = 1;

    enum DefaultMode {
      Disallow,
      Allow
    }

    struct SemaphoreState {
      DefaultMode defaultMode;
      bool allowsDelegateCalls;
      bool allowsValueCalls;

      // Counters which fit within one slot which allow for efficient checks
      uint64 numTotalExceptions;
      uint32 numSigExceptions;
      uint32 numAccountExceptions;
      uint32 numAccountSigExceptions;
    }

    // caller => state
    mapping (address => SemaphoreState) public state;
    // caller => sig => bool (whether executing functions with this sig on any account is an exception to caller's defaultMode)
    mapping (address => mapping (bytes4 => bool)) sigExceptions;
    // caller => account => bool (whether calling this account is an exception to caller's defaultMode)
    mapping (address => mapping (address => bool)) accountExceptions;
    // caller => account => sig => bool (whether executing functions with this sig on this account is an exception to caller's defaultMode)
    mapping (address => mapping (address => mapping (bytes4 => bool))) accountSigExceptions;

    error SemaphoreDisallowed();

    constructor() {
        // Initialize with impossible values in constructor so impl base cannot be used
        initialize(IMPL_INIT_NOOP_SAFE, false, IMPL_INIT_NOOP_ADDR);
    }

    function initialize(ISafe safe_, bool safeAllowsDelegateCalls, address trustedForwarder_) public {
        // calls SafeAware.__init_setSafe which reverts on reinitialization
        __init_firmBase(safe_, trustedForwarder_);

        // state[safe] represents the state when performing checks on the Safe multisig transactions checked via
        // Semaphore being set as the Safe's guard
        state[address(safe_)] = SemaphoreState({
            defaultMode: DefaultMode.Allow, // Safe is marked as allowed by default (too dangerous to disallow by default or leave as an option)
            allowsValueCalls: true, // Value calls are allowed by default for Safe
            allowsDelegateCalls: safeAllowsDelegateCalls,
            numTotalExceptions: 0,
            numSigExceptions: 0,
            numAccountExceptions: 0,
            numAccountSigExceptions: 0
        });
    }

    function setSemaphoreState(address account, DefaultMode defaultMode, bool allowsDelegateCalls, bool allowsValueCalls) external onlySafe {
        // TODO: think about not allowing to change defaultMode for Safe
        SemaphoreState memory s = state[account];
        s.defaultMode = defaultMode;
        s.allowsDelegateCalls = allowsDelegateCalls;
        s.allowsValueCalls = allowsValueCalls;
        state[account] = s;
    }

    // TODO: add/remove exceptions in batches

    function checkTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256, uint256, uint256, address, address payable, bytes memory, address
    ) external view {
        if (!canPerform(to, value, data, operation)) {
            revert SemaphoreDisallowed();
        }
    }

    function canPerform(address to, uint256 value, bytes calldata data, Enum.Operation operation) public view returns (bool) {
        address account = msg.sender;
        SemaphoreState memory s = state[account];

        if ((operation == Enum.Operation.DelegateCall && !s.allowsDelegateCalls) ||
            (value > 0 && !s.allowsValueCalls)) {
            return false;
        }

        return isException(s, account, to, data)
            ? s.defaultMode == DefaultMode.Disallow
            : s.defaultMode == DefaultMode.Allow;
    }

    function isException(SemaphoreState memory s, address from, address to, bytes calldata data) internal view returns (bool) {
        if (s.numTotalExceptions == 0) {
            return false;
        }

        bytes4 sig = data.length >= 4 ? bytes4(data[:4]) : bytes4(0);
        return
            s.numSigExceptions > 0 && sigExceptions[from][sig] ||
            s.numAccountExceptions > 0 && accountExceptions[from][to] ||
            s.numAccountSigExceptions > 0 && accountSigExceptions[from][to][sig];
    }

    function checkAfterExecution(bytes32 txHash, bool success) external {}
}