// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IExecutionHook
 * @notice Optional hook contract called before and after each execution in FlowForgeSafeModule.
 * @dev Deploy a contract implementing this interface and set it via FlowForgeSafeModule.setHook() to enable.
 */
interface IExecutionHook {
    function beforeExecution(
        address safeAddress,
        address actionTarget,
        uint256 actionValue,
        bytes calldata actionData,
        uint8 operation
    ) external;

    function afterExecution(
        address safeAddress,
        address actionTarget,
        uint256 actionValue,
        bytes calldata actionData,
        uint8 operation,
        bool success
    ) external;
}
