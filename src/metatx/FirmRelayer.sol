// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin/utils/cryptography/draft-EIP712.sol";

/**
 * @dev Custom ERC2771 forwarding relayer tailor made for Firm's UX needs
 * Inspired by https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.3/contracts/metatx/MinimalForwarder.sol (MIT licensed)
 */
 // One comment on EIP712 is that it is not well supported by hardware wallets
// like Trezor and Ledger so users may have issues signing messages with these
// hard ware wallets. Thought I hope support of EIP712 will improve over time
contract FirmRelayer is EIP712 {
    using ECDSA for bytes32;

    // NOTE: Assertions are its own separate array since it results in smaller calldata
    // than if the Call struct had an assertions array member for common cases
    // in which there will be one assertion per call and many calls will not
    // have assertions, resulting in more expensive encoding (1 more word for each empty array)
    struct RelayRequest {
        address from;
        uint256 nonce;
        Call[] calls;
        Assertion[] assertions;
    }

    struct Call {
        address to;
        uint256 value;
        uint256 gas;
        bytes data;
        uint256 assertionIndex; // one-indexed, 0 signals no assertions
    }

    struct Assertion {
        uint256 position;
        bytes32 expectedValue;
    }

    // See https://eips.ethereum.org/EIPS/eip-712#definition-of-typed-structured-data-%F0%9D%95%8A
    string internal constant ASSERTION_TYPE = "Assertion(uint256 position,bytes32 expectedValue)";
    string internal constant CALL_TYPE = "Call(address to,uint256 value,uint256 gas,bytes data,uint256 assertionIndex)";

    bytes32 internal constant REQUEST_TYPEHASH = keccak256(
        abi.encodePacked(
            "RelayRequest(address from,uint256 nonce,Call[] calls,Assertion[] assertions)", ASSERTION_TYPE, CALL_TYPE
        )
    );
    bytes32 internal constant ASSERTION_TYPEHASH = keccak256(abi.encodePacked(ASSERTION_TYPE));
    bytes32 internal constant CALL_TYPEHASH = keccak256(abi.encodePacked(CALL_TYPE));
    bytes32 internal constant ZERO_HASH = keccak256("");

    uint256 internal constant ASSERTION_WORD_SIZE = 32;

    mapping(address => uint256) public getNonce;

    error BadSignature();
    error BadNonce(uint256 expectedNonce);
    error CallExecutionFailed(uint256 callIndex, address to, bytes revertData);
    error BadAssertionIndex(uint256 callIndex);
    error AssertionPositionOutOfBounds(uint256 callIndex, uint256 returnDataLenght);
    error AssertionFailed(uint256 callIndex, bytes32 actualValue, bytes32 expectedValue);
    error UnauthorizedSenderNotFrom();

    event Relayed(address indexed relayer, address indexed signer, uint256 nonce, uint256 numCalls);
    event SelfRelayed(address indexed sender, uint256 numCalls);

    constructor() EIP712("Firm Relayer", "0.0.1") {}

    /**
     * @notice Verify whether a request has been signed properly
     * @param request RelayRequest containing the calls to be performed and assertions
     * @param signature signature of the EIP712 typed data hash of the request
     * @return true if the signature is a valid signature for the request
     */
    function verify(RelayRequest calldata request, bytes calldata signature) public view returns (bool) {
        (address signer, ECDSA.RecoverError error) = requestTypedDataHash(request).tryRecover(signature);

        return error == ECDSA.RecoverError.NoError && signer == request.from;
    }

    /**
     * @notice Relay a batch of calls checking assertions on behalf of a signer (ERC2771)
     * @param request RelayRequest containing the calls to be performed and assertions
     * @param signature signature of the EIP712 typed data hash of the request
     */
    function relay(RelayRequest calldata request, bytes calldata signature) external payable {
        if (!verify(request, signature)) {
            revert BadSignature();
        }

        address signer = request.from;
        if (getNonce[signer] != request.nonce) {
            revert BadNonce(getNonce[signer]);
        }
        getNonce[signer] = request.nonce + 1;

        _execute(signer, request.calls, request.assertions);

        emit Relayed(msg.sender, signer, request.nonce, request.calls.length);
    }

    /**
     * @notice Relay a batch of calls checking assertions for the sender
     * @dev The reason why someone may want to use this is both being able to
     * batch calls using the same mechanism as relayed requests plus checking
     * assertions.
     * NOTE: selfRelay doesn't increase an account's nonce (native account nonces are relied on)
     * @param calls Array of calls to be made
     * @param assertions Array of assertions that calls can use
     */
    function selfRelay(Call[] calldata calls, Assertion[] calldata assertions) external payable {
        _execute(msg.sender, calls, assertions);

        emit SelfRelayed(msg.sender, calls.length);
    }

    function _execute(address asSender, Call[] calldata calls, Assertion[] calldata assertions) internal {
        for (uint256 i = 0; i < calls.length;) {
            Call calldata call = calls[i];

            bytes memory payload = abi.encodePacked(call.data, asSender);
            (bool success, bytes memory returnData) = call.to.call{value: call.value, gas: call.gas}(payload);
            if (!success) {
                revert CallExecutionFailed(i, call.to, returnData);
            }

            uint256 assertionIndex = call.assertionIndex;
            if (assertionIndex != 0) {
                if (assertionIndex > assertions.length) {
                    revert BadAssertionIndex(i);
                }

                Assertion calldata assertion = assertions[assertionIndex - 1];
                uint256 returnDataMinLength = assertion.position + ASSERTION_WORD_SIZE;
                if (returnDataMinLength > returnData.length) {
                    revert AssertionPositionOutOfBounds(i, returnData.length);
                }

                bytes32 returnValue;
                /// @solidity memory-safe-assembly
                assembly {
                    // Position in memory for the value to be read is returnData + 0x20 + position
                    // so we can reuse returnDataMinLength (position + 32) from above as an optimization
                    returnValue := mload(add(returnData, returnDataMinLength))
                }
                if (returnValue != assertion.expectedValue) {
                    revert AssertionFailed(i, returnValue, assertion.expectedValue);
                }
            }
            unchecked {
                i++;
            }
        }
    }

    function requestTypedDataHash(RelayRequest calldata request) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(REQUEST_TYPEHASH, request.from, request.nonce, hash(request.calls), hash(request.assertions))
            )
        );
    }

    function hash(Call[] calldata calls) internal pure returns (bytes32) {
        uint256 length = calls.length;
        if (length == 0) {
            return ZERO_HASH;
        }
        bytes32[] memory hashes = new bytes32[](length);
        for (uint256 i = 0; i < length;) {
            Call calldata call = calls[i];
            hashes[i] = keccak256(
                abi.encode(CALL_TYPEHASH, call.to, call.value, call.gas, keccak256(call.data), call.assertionIndex)
            );
            unchecked {
                i++;
            }
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function hash(Assertion[] calldata assertions) internal pure returns (bytes32) {
        uint256 length = assertions.length;
        if (length == 0) {
            return ZERO_HASH;
        }
        bytes32[] memory hashes = new bytes32[](length);
        for (uint256 i = 0; i < length;) {
            Assertion calldata assertion = assertions[i];
            hashes[i] = keccak256(abi.encode(ASSERTION_TYPEHASH, assertion.position, assertion.expectedValue));
            unchecked {
                i++;
            }
        }
        return keccak256(abi.encodePacked(hashes));
    }
}
