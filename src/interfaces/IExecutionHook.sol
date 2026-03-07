// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IExecutionHook
 * @notice Optional hook contract called before and after each execution in FlowForgeSafeModule.
 * @dev Deploy a contract implementing this interface and set it via FlowForgeSafeModule.setHook() to enable.
 *      declaredUsdValue is in 8 decimals (e.g. 100_00000000 = 100 USD). Use 0 when not applicable.
 */
interface IExecutionHook {
    function beforeExecution(
        address safeAddress,
        address actionTarget,
        uint256 actionValue,
        bytes calldata actionData,
        uint8 operation,
        uint256 declaredUsdValue
    ) external;

    function afterExecution(
        address safeAddress,
        address actionTarget,
        uint256 actionValue,
        bytes calldata actionData,
        uint8 operation,
        bool success,
        uint256 declaredUsdValue
    ) external;
}
