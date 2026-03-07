// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IExecutionHook} from "./interfaces/IExecutionHook.sol";

/**
 * @title FlowForgeSpendingPolicy
 * @notice Execution hook that gates module execution by per-Safe policy: active, deadline, per-tx and daily USD limits.
 * @dev USD amounts use 8 decimals (e.g. 100_00000000 = 100 USD). Zero for spendLimitPerTx or dailyLimitUsd means no limit.
 */
contract FlowForgeSpendingPolicy is IExecutionHook {
    struct Policy {
        uint64 deadline;
        bool active;
        uint256 spendLimitPerTx; // 8 decimals; 0 = no per-tx limit
        uint256 dailyLimitUsd;   // 8 decimals; 0 = no daily limit
    }

    mapping(address safe => Policy) public policies;
    /// @dev dayIndex = block.timestamp / 1 days; spent amount in 8 decimals
    mapping(address safe => mapping(uint64 dayIndex => uint256)) public dailySpent;

    event PolicySet(address indexed safe, uint64 deadline, uint256 spendLimitPerTx, uint256 dailyLimitUsd);
    event PolicyRevoked(address indexed safe);

    error CallerMustBeContract();
    error InvalidDeadline();
    error PolicyNotActive(address safe);
    error PolicyExpired(address safe, uint64 deadline, uint256 timestamp);
    error ExceedsPerTxLimit(address safe, uint256 limit, uint256 declared);
    error ExceedsDailyLimit(address safe, uint256 limit, uint256 currentPlusDeclared);

    /**
     * @notice Set or update policy for the calling Safe.
     * @dev Intended to be called via a Safe transaction, so msg.sender is the Safe.
     *      Use 0 for spendLimitPerTx or dailyLimitUsd to indicate no limit for that dimension.
     */
    function setPolicy(uint64 deadline, uint256 spendLimitPerTx, uint256 dailyLimitUsd) external {
        if (msg.sender.code.length == 0) revert CallerMustBeContract();
        if (deadline <= block.timestamp) revert InvalidDeadline();

        policies[msg.sender] = Policy({
            deadline: deadline,
            active: true,
            spendLimitPerTx: spendLimitPerTx,
            dailyLimitUsd: dailyLimitUsd
        });
        emit PolicySet(msg.sender, deadline, spendLimitPerTx, dailyLimitUsd);
    }

    /**
     * @notice Revoke policy for the calling Safe.
     * @dev Intended to be called via a Safe transaction.
     */
    function revokePolicy() external {
        if (msg.sender.code.length == 0) revert CallerMustBeContract();

        policies[msg.sender].active = false;
        emit PolicyRevoked(msg.sender);
    }

    function beforeExecution(
        address safeAddress,
        address,
        uint256,
        bytes calldata,
        uint8,
        uint256 declaredUsdValue
    ) external view override {
        Policy memory policy = policies[safeAddress];
        if (!policy.active) revert PolicyNotActive(safeAddress);
        if (block.timestamp > policy.deadline) {
            revert PolicyExpired(safeAddress, policy.deadline, block.timestamp);
        }

        if (policy.spendLimitPerTx > 0 && declaredUsdValue > policy.spendLimitPerTx) {
            revert ExceedsPerTxLimit(safeAddress, policy.spendLimitPerTx, declaredUsdValue);
        }

        if (policy.dailyLimitUsd > 0) {
            uint64 dayIndex = uint64(block.timestamp / 1 days);
            uint256 current = dailySpent[safeAddress][dayIndex];
            uint256 currentPlusDeclared = current + declaredUsdValue;
            if (currentPlusDeclared > policy.dailyLimitUsd) {
                revert ExceedsDailyLimit(safeAddress, policy.dailyLimitUsd, currentPlusDeclared);
            }
        }
    }

    function afterExecution(
        address safeAddress,
        address,
        uint256,
        bytes calldata,
        uint8,
        bool success,
        uint256 declaredUsdValue
    ) external override {
        if (success && declaredUsdValue > 0) {
            uint64 dayIndex = uint64(block.timestamp / 1 days);
            dailySpent[safeAddress][dayIndex] += declaredUsdValue;
        }
    }
}
