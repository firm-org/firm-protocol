// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {Clones} from "openzeppelin/proxy/Clones.sol";

import {FirmBase, IMPL_INIT_NOOP_SAFE, IMPL_INIT_NOOP_ADDR} from "../bases/FirmBase.sol";
import {ISafe} from "../bases/ISafe.sol";

import {EquityToken, ERC20, ERC20Votes} from "./EquityToken.sol";
import {IBouncer} from "./bouncers/IBouncer.sol";
import {IAccountController} from "./controllers/AccountController.sol";

uint32 constant NO_CONVERSION_FLAG = type(uint32).max;

contract Captable is FirmBase {
    using Clones for address;

    string public constant moduleId = "org.firm.captable";
    uint256 public constant moduleVersion = 1;

    address immutable internal equityTokenImpl;

    string public name;

    struct Class {
        EquityToken token;
        uint64 votingWeight;
        uint32 convertsIntoClassId;
        uint256 authorized;
        uint256 convertible;
        string name;
        string ticker;
    }

    mapping(uint256 => Class) public classes;
    uint256 public classCount;

    mapping(address => mapping(uint256 => IAccountController)) controllers;

    // Above this limit, voting power getters that iterate through all tokens become
    // very expensive. See `CaptableClassLimitTest` tests for worst-case benchmarks
    uint32 internal constant CLASSES_LIMIT = 128;

    error ClassCreationAboveLimit();
    error UnexistentClass(uint256 classId);
    error BadInput();
    error TransferBlocked(IBouncer bouncer, address from, address to, uint256 classId, uint256 amount);
    error ConversionBlocked(IAccountController controller, address account, uint256 classId, uint256 amount);
    error UnauthorizedNotController();
    error IssuingOverAuthorized(uint256 classId);
    error ConvertibleOverAuthorized(uint256 classId);

    constructor() {
        initialize(IMPL_INIT_NOOP_SAFE, "", IBouncer(IMPL_INIT_NOOP_ADDR));
        equityTokenImpl = address(new EquityToken());
    }

    function initialize(ISafe safe_, string memory name_, IBouncer globalBouncer_) public {
        __init_setSafe(safe_);
        name = name_;
        // globalControls.bouncer = _globalBouncer;
        // globalControls.canIssue[address(_safe)] = true;
    }

    function createClass(
        string calldata className,
        string calldata ticker,
        uint256 authorized,
        uint32 convertsIntoClassId,
        uint64 votingWeight
    )
        external
        onlySafe
        returns (uint256 classId, EquityToken token)
    {
        unchecked {
            if ((classId = classCount++) >= CLASSES_LIMIT) {
                revert ClassCreationAboveLimit();
            }
        }

        // When creating the first class, unless convertsIntoClassId == NO_CONVERSION_FLAG,
        // this will implicitly revert, since there's no convertsIntoClassId for which
        // _getClass() won't revert
        if (convertsIntoClassId != NO_CONVERSION_FLAG) {
            Class storage conversionClass = _getClass(convertsIntoClassId);
            uint256 newConvertible = conversionClass.convertible + authorized;

            if (conversionClass.token.totalSupply() + newConvertible > conversionClass.authorized) {
                revert ConvertibleOverAuthorized(convertsIntoClassId);
            }

            conversionClass.convertible = newConvertible;
        }

        token = EquityToken(equityTokenImpl.cloneDeterministic(bytes32(classId)));
        token.initialize(this, uint32(classId));

        Class storage class = classes[classId];
        class.token = token;
        class.votingWeight = votingWeight;
        class.authorized = authorized;
        class.name = className;
        class.ticker = ticker;
        class.convertsIntoClassId = convertsIntoClassId;
    }

    function issue(address account, uint256 classId, uint256 amount) public {
        if (amount == 0) {
            revert BadInput();
        }

        // TODO: issue access control

        Class storage class = _getClass(classId);

        if (class.token.totalSupply() + class.convertible + amount > class.authorized) {
            revert IssuingOverAuthorized(classId);
        }

        class.token.mint(account, amount);
    }

    function issueControlled(
        address account,
        uint256 classId,
        uint256 amount,
        IAccountController controller,
        bytes calldata controllerParams
    )
        external
    {
        issue(account, classId, amount);
        controllers[account][classId] = controller;
        controller.addAccount(account, classId, amount, controllerParams);
    }

    function controllerForfeit(address account, address to, uint256 classId, uint256 amount) external {
        if (msg.sender != address(controllers[account][classId])) {
            revert UnauthorizedNotController();
        }

        _getClass(classId).token.forfeit(account, to, amount);
    }

    function convert(uint256 classId, uint256 amount) external {
        Class storage fromClass = _getClass(classId);
        Class storage toClass = _getClass(fromClass.convertsIntoClassId);

        IAccountController controller = controllers[msg.sender][classId];
        // converter has a controller for the converting class id
        if (address(controller) != address(0)) {
            if (!controller.isTransferAllowed(msg.sender, msg.sender, classId, amount)) {
                revert ConversionBlocked(controller, msg.sender, classId, amount);
            }
        }

        fromClass.authorized -= amount;
        toClass.convertible -= amount;

        fromClass.token.burn(msg.sender, amount);
        toClass.token.mint(msg.sender, amount);
    }

    // Reverts if transfer isn't allowed so that the revert reason can bubble up
    // If a state update is necessary, we could return a flag from this function
    // and commit that state after tokens are transferred in a separate call?
    function ensureTransferIsAllowed(address from, address to, uint256 classId, uint256 amount) external view {
        Class storage class = _getClass(classId);

        // NOTE: adopting bouncers from initial iteration

        IAccountController controller = controllers[from][classId];

        // from has a controller for this class id
        if (address(controller) != address(0)) {
            if (!controller.isTransferAllowed(from, to, classId, amount)) {
                revert TransferBlocked(controller, from, to, classId, amount);
            }
        }
    }

    function balanceOf(address account, uint256 classId) public view returns (uint256) {
        return _getClass(classId).token.balanceOf(account);
    }

    function getVotes(address account) external view returns (uint256 totalVotes) {
        return _weightedSumAllClasses(abi.encodeCall(ERC20Votes.getVotes, (account)));
    }

    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256) {
        return _weightedSumAllClasses(abi.encodeCall(ERC20Votes.getPastVotes, (account, blockNumber)));
    }

    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256) {
        return _weightedSumAllClasses(abi.encodeCall(ERC20Votes.getPastTotalSupply, (blockNumber)));
    }

    function getTotalVotes() external view returns (uint256) {
        return _weightedSumAllClasses(abi.encodeCall(ERC20.totalSupply, ()));
    }

    function _weightedSumAllClasses(bytes memory data) internal view returns (uint256 total) {
        uint256 n = classCount;
        for (uint256 i = 0; i < n;) {
            Class storage class = classes[i];
            uint256 votingWeight = class.votingWeight;
            if (votingWeight > 0) {
                (bool ok, bytes memory returnData) = address(class.token).staticcall(data);
                require(ok && returnData.length == 32);
                total += votingWeight * abi.decode(returnData, (uint256));
            }
            unchecked {
                i++;
            }
        }
    }

    function nameFor(uint256 classId) public view returns (string memory) {
        return string(abi.encodePacked(name, bytes(": "), _getClass(classId).name));
    }

    function tickerFor(uint256 classId) public view returns (string memory) {
        return _getClass(classId).ticker;
    }

    function _getClass(uint256 classId) internal view returns (Class storage) {
        if (classId >= classCount) {
            revert UnexistentClass(classId);
        }
        return classes[classId];
    }
}
