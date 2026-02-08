// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IExecutionHook} from "./interfaces/IExecutionHook.sol";

/**
 * @dev Minimal interface for Gnosis Safe's execTransactionFromModule used by this module.
 */
interface IGnosisSafe {
    function execTransactionFromModule(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        returns (bool success);
}

/**
 * @title FlowForgeSafeModule
 * @notice Safe module that allows a trusted executor to run tasks on user Safes, with optional before/after hooks.
 * @dev Only the executor can call execTask. Only the owner can set the executor and the hook. Deploy a contract
 *      implementing IExecutionHook and set it via setHook() when you need hook functionality.
 */
contract FlowForgeSafeModule is Ownable, ReentrancyGuard {
    // Address allowed to call execTask (e.g. relayer or backend). Updatable by owner.
    address public executor;

    // Optional hook contract for beforeExecution / afterExecution. Zero address means no hook.
    address public hook;

    event TaskExecuted(address indexed safeAddress, address indexed caller, bool success);
    event HookSet(address indexed previousHook, address indexed newHook);
    event ExecutorSet(address indexed previousExecutor, address indexed newExecutor);

    error NotExecutor();
    error ExecFailed();

    modifier onlyExecutor() {
        _onlyExecutor();
        _;
    }

    function _onlyExecutor() internal view {
        if (msg.sender != executor) revert NotExecutor();
    }

    constructor(address _executor) Ownable(msg.sender) {
        require(_executor != address(0), "Zero executor");
        executor = _executor;
    }

    /**
     * @notice Set the address allowed to call execTask. Only the owner can call this.
     * @param _executor New executor address. Must not be zero.
     */
    function setExecutor(address _executor) external onlyOwner {
        require(_executor != address(0), "Zero executor");
        address previous = executor;
        executor = _executor;
        emit ExecutorSet(previous, _executor);
    }

    /**
     * @notice Set the execution hook contract. Only the owner can call this.
     * @dev Pass address(0) to disable hooks. The contract at hookAddress should implement IExecutionHook.
     * @param hookAddress Address of the hook contract, or zero to clear.
     */
    function setHook(address hookAddress) external onlyOwner {
        address previous = hook;
        hook = hookAddress;
        emit HookSet(previous, hookAddress);
    }

    /**
     * @notice Execute a task on a Safe. Only the executor can call this.
     * @dev If a hook is set, calls hook.beforeExecution() first (revert there aborts the run),
     *      then executes the Safe transaction, then calls hook.afterExecution(success). Reverts if the Safe execution fails.
     * @param safeAddress The Safe contract that will execute the action.
     * @param actionTarget The contract to call (to).
     * @param actionValue ETH value to send with the call.
     * @param actionData Calldata for the call.
     * @param operation 0 = CALL, 1 = DELEGATECALL (Safe enum).
     * @return success True if the Safe executed the transaction successfully.
     */
    function execTask(
        address safeAddress,
        address actionTarget,
        uint256 actionValue,
        bytes calldata actionData,
        uint8 operation
    ) external nonReentrant onlyExecutor returns (bool success) {
        if (hook != address(0)) {
            IExecutionHook(hook).beforeExecution(safeAddress, actionTarget, actionValue, actionData, operation);
        }

        IGnosisSafe safe = IGnosisSafe(safeAddress);
        bool ok;
        try safe.execTransactionFromModule(actionTarget, actionValue, actionData, operation) returns (bool _success) {
            ok = _success;
        } catch {
            ok = false;
        }

        if (hook != address(0)) {
            IExecutionHook(hook).afterExecution(safeAddress, actionTarget, actionValue, actionData, operation, ok);
        }

        if (!ok) {
            emit TaskExecuted(safeAddress, msg.sender, false);
            revert ExecFailed();
        }

        emit TaskExecuted(safeAddress, msg.sender, true);
        return true;
    }
}
