// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAggregatorV3
 * @notice Minimal Chainlink price feed interface (latestRoundData).
 * @dev Price has 8 decimals (e.g. 2000_00000000 = $2000).
 */
interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
