// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFlowForgeSubdomainPricer
 * @notice Returns price for registering or renewing a subdomain. Supports ETH or ERC-20.
 * @dev token == address(0) means the user must send ETH (msg.value); otherwise they must approve ERC-20.
 */
interface IFlowForgeSubdomainPricer {
    /// @param parentNode Namehash of the parent (e.g. flowforge.eth).
    /// @param label Subdomain label (e.g. "alice" for alice.flowforge.eth).
    /// @param duration Registration or renewal duration in seconds.
    /// @return token Address(0) for ETH; otherwise ERC-20 token contract.
    /// @return price Amount the user must pay (wei for ETH, token units for ERC-20).
    function price(
        bytes32 parentNode,
        string calldata label,
        uint256 duration
    ) external view returns (address token, uint256 price);
}
