// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/**
 * @title FlowForgeDeployed
 * @notice Tests against deployed contracts on Arbitrum Sepolia (chain id 421614).
 * @dev Run with: forge test --match-contract FlowForgeDeployed --fork-url $ARB_SEPOLIA_RPC_URL
 *      Deployed addresses are in deployments.json; update ADDRESSES when you redeploy.
 */
contract FlowForgeDeployed is Test {
    uint256 constant ARB_SEPOLIA = 421614;

    address constant FACTORY = 0x3d7A286b5E28E766e0864fa6042C33a522b8c332;
    address constant MODULE = 0x45267664d61Ef71B538df5f1c95Ac40C6B51d1bC;
    address constant SPENDING_POLICY = 0x983b8B075B4baa6c91013F03F2C7AA357D98B8dc;

    function setUp() public {
        vm.createSelectFork("arb_sepolia");
    }

    function test_factory_has_owner_and_executor() public view {
        address owner = _callAddress(FACTORY, "owner()");
        address executor = _callAddress(FACTORY, "executor()");
        assertTrue(owner != address(0), "factory owner should be set");
        assertTrue(executor != address(0), "factory executor should be set");
    }

    function test_factory_immutables() public view {
        (bool ok,) = FACTORY.staticcall(abi.encodeWithSignature("SAFE_PROXY_FACTORY()"));
        assertTrue(ok, "SAFE_PROXY_FACTORY");
        (ok,) = FACTORY.staticcall(abi.encodeWithSignature("SAFE_SINGLETON()"));
        assertTrue(ok, "SAFE_SINGLETON");
    }

    function test_module_has_owner_executor_and_hook() public view {
        address owner = _callAddress(MODULE, "owner()");
        address executor = _callAddress(MODULE, "executor()");
        address hook = _callAddress(MODULE, "hook()");
        assertTrue(owner != address(0), "module owner");
        assertTrue(executor != address(0), "module executor");
        assertEq(hook, SPENDING_POLICY, "module hook should be spending policy");
    }

    function test_spending_policy_policies_slot_readable() public view {
        // policies(safe) returns (uint64 deadline, bool active, uint256 spendLimitPerTx, uint256 dailyLimitUsd)
        address anySafe = address(0x1234);
        (bool success,) = SPENDING_POLICY.staticcall(
            abi.encodeWithSignature("policies(address)", anySafe)
        );
        assertTrue(success, "policies(safe) should not revert");
    }

    function test_spending_policy_dailySpent_readable() public view {
        (bool success,) = SPENDING_POLICY.staticcall(
            abi.encodeWithSignature("dailySpent(address,uint64)", address(0x1), uint64(block.timestamp / 1 days))
        );
        assertTrue(success, "dailySpent(safe, day) should not revert");
    }

    function _callAddress(address target, string memory sig) internal view returns (address) {
        (bool ok, bytes memory ret) = target.staticcall(abi.encodeWithSignature(sig));
        require(ok, "call failed");
        return abi.decode(ret, (address));
    }
}

