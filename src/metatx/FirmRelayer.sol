// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin/utils/cryptography/draft-EIP712.sol";

/**
 * @dev Custom ERC2771 forwarding relayer tailor made for Firm's UX needs
 * Inspired by https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.7.3/contracts/metatx/MinimalForwarder.sol (MIT licensed)
 */
contract FirmRelayer is EIP712 {
    using ECDSA for bytes32;

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
        uint256 nonce;
        bytes data;
        uint256 assertionIndex; // one-indexed, 0 signals no assertions
    }

    struct Assertion {
        uint256 position;
        bytes32 expectedValue;
    }

    // See https://eips.ethereum.org/EIPS/eip-712#definition-of-typed-structured-data-%F0%9D%95%8A
    string internal constant ASSERTION_TYPE = "Assertion(uint256 position,bytes32 expectedValue)";
    string internal constant CALL_TYPE = "Call(address to,uint256 value,uint256 gas,uint256 nonce,bytes data,uint256 assertionIndex)";

    bytes32 internal constant REQUEST_TYPEHASH =
        keccak256(abi.encodePacked("RelayRequest(address from,uint256 nonce,Call[] calls,Assertion[] assertions)", ASSERTION_TYPE, CALL_TYPE));
    bytes32 internal constant ASSERTION_TYPEHASH = keccak256(abi.encodePacked(ASSERTION_TYPE));
    bytes32 internal constant CALL_TYPEHASH = keccak256(abi.encodePacked(CALL_TYPE));

    uint256 internal constant ASSERTION_WORD_SIZE = 32;

    mapping(address => uint256) public getNonce;

    error BadSignature();
    error BadNonce(uint256 expectedNonce);
    error CallExecutionFailed(uint256 callIndex, bytes revertData);
    error BadAssertionIndex(uint256 callIndex);
    error AssertionPositionOutOfBounds(uint256 callIndex, uint256 returnDataLenght);
    error AssertionFailed(uint256 callIndex, bytes32 actualValue, bytes32 expectedValue);

    constructor() EIP712("FirmRelayer", "0.0.1") {}

    function verify(RelayRequest calldata request, bytes calldata signature) public view returns (bool) {
        return requestTypedDataHash(request).recover(signature) == request.from;
    }

    function relay(RelayRequest calldata request, bytes calldata signature) external payable {
        if (!verify(request, signature)) {
            revert BadSignature();
        }

        address signer = request.from;
        if (getNonce[signer] != request.nonce) {
            revert BadNonce(getNonce[signer]);
        }
        getNonce[signer] = request.nonce + 1;

        for (uint256 i = 0; i < request.calls.length;) {
            Call memory call = request.calls[i];

            bytes memory payload = abi.encodePacked(call.data, signer);
            (bool success, bytes memory returnData) = call.to.call{ value: call.value, gas: call.gas }(payload);

            if (!success) {
                revert CallExecutionFailed(i, returnData);
            }

            uint256 assertionIndex = call.assertionIndex;
            if (assertionIndex != 0) {
                if (assertionIndex > request.assertions.length) {
                    revert BadAssertionIndex(i);
                }

                Assertion memory assertion = request.assertions[assertionIndex - 1];
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
            keccak256(abi.encode(REQUEST_TYPEHASH, request.from, request.nonce, hash(request.calls), hash(request.assertions)))
        );
    }

    function hash(Call[] calldata calls) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](calls.length);
        for (uint256 i = 0; i < calls.length;) {
            Call calldata call = calls[i];
            hashes[i] = keccak256(abi.encode(CALL_TYPEHASH, call.to, call.value, call.nonce, keccak256(call.data), call.assertionIndex));
            unchecked {
                i++;
            }
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function hash(Assertion[] calldata assertions) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](assertions.length);
        for (uint256 i = 0; i < assertions.length;) {
            Assertion calldata assertion = assertions[i];
            hashes[i] = keccak256(abi.encode(ASSERTION_TYPEHASH, assertion.position, assertion.expectedValue));
            unchecked {
                i++;
            }
        }
        return keccak256(abi.encodePacked(hashes));
    }
}