// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TStorage} from "./TStorage.sol";
import {Encoding} from "../external/Encoding.sol";

/// @title UniqueArray Library
/// @notice Provides utility functions to extract unique elements from arrays, leveraging transient storage to track occurrences.
library UniqueArray {
    using TStorage for uint256;
    using TStorage for address;

    // @notice Extracts unique elements from an array of uint256
    /// @param input The array of uint256 from which unique elements are to be extracted
    /// @return uniqueElements An array of unique uint256 elements from the input
    function extractUnique(uint256[] memory input) internal returns (uint256[] memory) {
        uint256 index;
        uint256[] memory uniqueElements = new uint256[](input.length);

        for (uint256 i = 0; i < input.length; i++) {
            uint256 element = input[i];

            if (element.tload() == 0) {
                unchecked {
                    uniqueElements[index++] = element;
                }
                element.tstore(1);
            }
        }

        // Resize the unique elements array to include only the elements added
        assembly ("memory-safe") {
            mstore(uniqueElements, index)
        }

        return uniqueElements;
    }

    /// @notice Extracts unique elements from an array of addresses
    /// @param input The array of addresses from which unique elements are to be extracted
    /// @return uniqueElements An array of unique address elements from the input
    function extractUnique(address[] memory input) internal returns (address[] memory) {
        uint256 index;
        address[] memory uniqueElements = new address[](input.length);

        for (uint256 i = 0; i < input.length; i++) {
            address element = input[i];

            if (element.tload() == 0) {
                unchecked {
                    uniqueElements[index++] = element;
                }
                element.tstore(1);
            }
        }

        // Resize the unique elements array
        assembly ("memory-safe") {
            mstore(uniqueElements, index)
        }

        return uniqueElements;
    }

    /// @notice Extracts unique market IDs from an array of uint256, where each element is a sub-ID encoding market details
    /// @param input The array of sub-IDs from which unique market IDs are to be extracted
    /// @return uniqueElements An array of unique market IDs extracted from the sub-IDs
    function extractUniqueMarketId(uint256[] memory input) internal returns (uint256[] memory) {
        uint256 index;
        uint256[] memory uniqueElements = new uint256[](input.length);

        for (uint256 i = 0; i < input.length; i++) {
            unchecked {
                (uint256 element,,,) = Encoding.fromSubId(uint112(input[i]));

                if (element.tload() == 0) {
                    uniqueElements[index++] = element;
                }
                element.tstore(1);
            }
        }

        // Resize the unique elements array
        assembly ("memory-safe") {
            mstore(uniqueElements, index)
        }

        return uniqueElements;
    }
}
