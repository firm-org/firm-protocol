// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {Clones} from "openzeppelin/proxy/Clones.sol";

import {FirmBase, IMPL_INIT_NOOP_SAFE, IMPL_INIT_NOOP_ADDR} from "../bases/FirmBase.sol";
import {ISafe} from "../bases/ISafe.sol";

import {EquityToken, ERC20, ERC20Votes} from "./EquityToken.sol";
import {BouncerChecker} from "./BouncerChecker.sol";
import {IBouncer} from "./bouncers/IBouncer.sol";
import {IAccountController} from "./controllers/AccountController.sol";

uint32 constant NO_CONVERSION_FLAG = type(uint32).max;

contract Captable is FirmBase, BouncerChecker {
    using Clones for address;

    string public constant moduleId = "org.firm.captable";
    uint256 public constant moduleVersion = 1;

    address immutable internal equityTokenImpl;

    struct Class {
        EquityToken token;
        uint64 votingWeight;
        uint32 convertsIntoClassId;
        uint256 authorized;
        uint256 convertible;
        string name;
        string ticker;
        IBouncer bouncer;
        bool isFrozen;
        mapping(address => bool) isManager;
    }

    string public name;
    mapping(uint256 => Class) public classes;
    uint256 internal classCount;

    mapping(address => mapping(uint256 => IAccountController)) controllers;

    // Above this limit, voting power getters that iterate through all tokens become
    // very expensive. See `CaptableClassLimitTest` tests for worst-case benchmarks
    uint32 internal constant CLASSES_LIMIT = 128;

    error ClassCreationAboveLimit();
    error UnexistentClass(uint256 classId);
    error BadInput();
    error FrozenClass(uint256 classId);
    error TransferBlocked(IBouncer bouncer, address from, address to, uint256 classId, uint256 amount);
    error ConversionBlocked(IAccountController controller, address account, uint256 classId, uint256 amount);
    error UnauthorizedNotController();
    error IssuedOverAuthorized(uint256 classId);
    error ConvertibleOverAuthorized(uint256 classId);
    error UnauthorizedNotManager(uint256 classId);

    constructor() {
        initialize(IMPL_INIT_NOOP_SAFE, "");
        equityTokenImpl = address(new EquityToken());
    }

    function initialize(ISafe safe_, string memory name_) public {
        __init_setSafe(safe_);
        name = name_;
    }

    function createClass(
        string calldata className,
        string calldata ticker,
        uint256 authorized,
        uint32 convertsIntoClassId,
        uint64 votingWeight,
        IBouncer bouncer
    )
        external
        onlySafe
        returns (uint256 classId, EquityToken token)
    {
        if (authorized == 0 || address(bouncer) == address(0)) {
            revert BadInput();
        }
        unchecked {
            if ((classId = classCount++) >= CLASSES_LIMIT) {
                revert ClassCreationAboveLimit();
            }
        }

        // When creating the first class, unless convertsIntoClassId == NO_CONVERSION_FLAG,
        // this will implicitly revert, since there's no convertsIntoClassId for which
        // _getClass() won't revert (_getClass() is called within _changeConvertibleAmount())
        if (convertsIntoClassId != NO_CONVERSION_FLAG) {
            _changeConvertibleAmount(convertsIntoClassId, authorized, true);
        }

        // Deploys token with a non-upgradeable EIP-1967 token
        // Doesn't use create2 since the salt would just be the classId and this account's nonce is just as good
        token = EquityToken(equityTokenImpl.clone());
        token.initialize(this, uint32(classId));

        Class storage class = classes[classId];
        class.token = token;
        class.votingWeight = votingWeight;
        class.authorized = authorized;
        class.name = className;
        class.ticker = ticker;
        class.convertsIntoClassId = convertsIntoClassId;
        class.bouncer = bouncer;
        class.isManager[msg.sender] = true; // safe addr is set as manager for class
    }

    function setAuthorized(uint256 classId, uint256 newAuthorized) onlySafe external {
        if (newAuthorized == 0) {
            revert BadInput();
        }

        Class storage class = _getClass(classId);

        _ensureClassNotFrozen(class, classId);

        uint256 oldAuthorized = class.authorized;
        bool isDecreasing = newAuthorized < oldAuthorized;

        // When decreasing the authorized amount, make sure that the issued amount
        // plus the convertible amount doesn't exceed the new authorized amount
        if (isDecreasing) {
            if (_issuedFor(class) + class.convertible > newAuthorized) {
                revert IssuedOverAuthorized(classId);
            }
        }

        // If the class converts into another class, update the convertible amount of that class
        if (class.convertsIntoClassId != NO_CONVERSION_FLAG) {
            uint256 delta = isDecreasing ? oldAuthorized - newAuthorized : newAuthorized - oldAuthorized;
            _changeConvertibleAmount(class.convertsIntoClassId, delta, !isDecreasing);
        }

        class.authorized = newAuthorized;
    }

    function _changeConvertibleAmount(uint256 classId, uint256 amount, bool isIncrease) internal {
        Class storage class = _getClass(classId);
        uint256 newConvertible = isIncrease ? class.convertible + amount : class.convertible - amount;

        // Ensure that there's enough authorized space for the new convertible if we are increasing
        if (isIncrease && _issuedFor(class) + newConvertible > class.authorized) {
            revert ConvertibleOverAuthorized(classId);
        }

        class.convertible = newConvertible;
    }

    function setBouncer(uint256 classId, IBouncer bouncer) onlySafe external {
        if (address(bouncer) == address(0)) {
            revert BadInput();
        }

        Class storage class = _getClass(classId);

        _ensureClassNotFrozen(class, classId);

        class.bouncer = bouncer;
    }

    function setManager(uint256 classId, address manager, bool isManager) onlySafe external {
        Class storage class = _getClass(classId);

        _ensureClassNotFrozen(class, classId);

        class.isManager[manager] = isManager;
    }

    function freeze(uint256 classId) onlySafe external {
        Class storage class = _getClass(classId);

        _ensureClassNotFrozen(class, classId);

        class.isFrozen = true;
    }

    function _ensureClassNotFrozen(Class storage class, uint256 classId) internal view {
        if (class.isFrozen) {
            revert FrozenClass(classId);
        }
    }

    function _ensureSenderIsManager(Class storage class, uint256 classId) internal view {
        if (!class.isManager[_msgSender()]) {
            revert UnauthorizedNotManager(classId);
        }
    }

    function issue(address account, uint256 classId, uint256 amount) public {
        if (amount == 0) {
            revert BadInput();
        }

        Class storage class = _getClass(classId);
        _ensureSenderIsManager(class, classId);

        if (_issuedFor(class) + class.convertible + amount > class.authorized) {
            revert IssuedOverAuthorized(classId);
        }

        class.token.mint(account, amount);
    }

    function issueAndSetController(
        address account,
        uint256 classId,
        uint256 amount,
        IAccountController controller,
        bytes calldata controllerParams
    ) external {
        // `issue` verifies that the class exists and sender is manager on classId
        issue(account, classId, amount);
        _setController(
            account,
            classId,
            amount,
            controller,
            controllerParams
        );
    }

    function setController(
        address account,
        uint256 classId,
        IAccountController controller,
        bytes calldata controllerParams
    ) external {
        Class storage class = _getClass(classId);
        _ensureSenderIsManager(class, classId);
        _setController(
            account,
            classId,
            class.token.balanceOf(account),
            controller,
            controllerParams
        );
    }

    function _setController(
        address account,
        uint256 classId,
        uint256 amount,
        IAccountController controller,
        bytes calldata controllerParams
    ) internal {
        controllers[account][classId] = controller;
        controller.addAccount(account, classId, amount, controllerParams);
    }

    function controllerForcedTransfer(address account, address to, uint256 classId, uint256 amount, string calldata reason) external {
        // Controllers use msg.sender directly as they should be contracts that
        // call this one and should never be using metatxs
        if (msg.sender != address(controllers[account][classId])) {
            revert UnauthorizedNotController();
        }

        _getClass(classId).token.forcedTransfer(account, to, amount, msg.sender, reason);
    }

    function managerForcedTransfer(address account, address to, uint256 classId, uint256 amount, string calldata reason) external {
        Class storage class = _getClass(classId);

        _ensureSenderIsManager(class, classId);

        class.token.forcedTransfer(account, to, amount, msg.sender, reason);
    }

    function convert(uint256 classId, uint256 amount) external {
        Class storage fromClass = _getClass(classId);
        Class storage toClass = _getClass(fromClass.convertsIntoClassId);

        address sender = _msgSender();

        IAccountController controller = controllers[sender][classId];
        // if user has a controller for the origin class id
        if (address(controller) != address(0)) {
            if (!controller.isTransferAllowed(sender, sender, classId, amount)) {
                revert ConversionBlocked(controller, sender, classId, amount);
            }
        }

        fromClass.authorized -= amount;
        toClass.convertible -= amount;

        fromClass.token.burn(sender, amount);
        toClass.token.mint(sender, amount);
    }

    // Reverts if transfer isn't allowed so that the revert reason can bubble up
    // If a state update is necessary, we could return a flag from this function
    // and commit that state after tokens are transferred in a separate call?
    function ensureTransferIsAllowed(address from, address to, uint256 classId, uint256 amount) external view {
        Class storage class = _getClass(classId);

        // First, ensure the class bouncer allows the transfer
        if (!bouncerAllowsTransfer(class.bouncer, from, to, classId, amount)) {
            revert TransferBlocked(class.bouncer, from, to, classId, amount);
        }

        // Then, if the holder has a controller for their shares in this class, check that
        // it allows the transfer
        IAccountController controller = controllers[from][classId];
        // from has a controller for this class id
        if (address(controller) != address(0)) {
            if (!controller.isTransferAllowed(from, to, classId, amount)) {
                revert TransferBlocked(controller, from, to, classId, amount);
            }
        }
    }

    function numberOfClasses() public view override returns (uint256) {
        return classCount;
    }

    function authorizedFor(uint256 classId) external view returns (uint256) {
        return _getClass(classId).authorized;
    }

    function issuedFor(uint256 classId) external view returns (uint256) {
        return _issuedFor(_getClass(classId));
    }

    function _issuedFor(Class storage class) internal view returns (uint256) {
        return class.token.totalSupply();
    }

    function balanceOf(address account, uint256 classId) public view override returns (uint256) {
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

    function _getClass(uint256 classId) internal view returns (Class storage class) {
        class = classes[classId];

        if (address(class.token) == address(0)) {
            revert UnexistentClass(classId);
        }
    }
}
