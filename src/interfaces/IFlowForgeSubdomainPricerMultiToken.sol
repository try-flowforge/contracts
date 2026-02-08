// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFlowForgeSubdomainPricerMultiToken
 * @notice Optional extension: return price for a specific payment token (ETH or ERC-20).
 * @dev paymentToken == address(0) means ETH (return value in wei); otherwise ERC-20 (return value in token units).
 */
interface IFlowForgeSubdomainPricerMultiToken {
    function priceForToken(
        bytes32 parentNode,
        string calldata label,
        uint256 duration,
        address paymentToken
    ) external view returns (uint256 price);
}
