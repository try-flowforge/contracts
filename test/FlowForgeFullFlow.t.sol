// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

interface IFactoryMinimal {
    function owner() external view returns (address);
    function executor() external view returns (address);
    function createSafeWallet(address user) external returns (address);
}

interface IModuleMinimal {
    function executor() external view returns (address);
    function execTask(address safeAddress, address actionTarget, uint256 actionValue, bytes calldata actionData, uint8 operation, uint256 declaredUsdValue) external returns (bool);
}

interface ISafeMinimal {
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);
    function nonce() external view returns (uint256);
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        bytes memory signatures
    ) external payable returns (bool);
}

/**
 * @title FlowForgeFullFlow
 * @notice Full execution flow on a fork: create Safe via factory, enable module, set spending policy, execTask to test contract.
 * @dev Uses PRIVATE_KEY (owner) for createSafeWallet, EXECUTOR_PRIVATE_KEY for execTask.
 *      FLOWFORGE_TEST_CONTRACT = deployed test contract address.
 *      Run: forge test --match-contract FlowForgeFullFlow --fork-url $ARB_SEPOLIA_RPC_URL
 */
contract FlowForgeFullFlow is Test {
    uint256 constant ARB_SEPOLIA = 421614;

    address constant FACTORY = 0x3d7A286b5E28E766e0864fa6042C33a522b8c332;
    address constant MODULE = 0x45267664d61Ef71B538df5f1c95Ac40C6B51d1bC;
    address constant SPENDING_POLICY = 0x983b8B075B4baa6c91013F03F2C7AA357D98B8dc;

    uint256 ownerPrivateKey;
    uint256 executorPrivateKey;
    address owner;
    address executor;
    address safeAddress;
    address testContract;

    function setUp() public {
        vm.createSelectFork("arb_sepolia");
        ownerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        executorPrivateKey = vm.envOr("EXECUTOR_PRIVATE_KEY", uint256(0));
        if (ownerPrivateKey == 0 || executorPrivateKey == 0) {
            return;
        }
        owner = vm.addr(ownerPrivateKey);
        executor = vm.addr(executorPrivateKey);
        testContract = vm.envOr("FLOWFORGE_TEST_CONTRACT", address(0));
        if (testContract == address(0)) {
            return;
        }
    }

    function test_fullFlow_createSafe_enableModule_setPolicy_execTask() public {
        if (ownerPrivateKey == 0 || executorPrivateKey == 0 || testContract == address(0)) {
            vm.skip(true);
            return;
        }
        bool ok;
        address factoryOwner = IFactoryMinimal(FACTORY).owner();
        address factoryExecutor = IFactoryMinimal(FACTORY).executor();
        if (owner != factoryOwner && owner != factoryExecutor) {
            vm.skip(true); // PRIVATE_KEY must be factory owner or executor
            return;
        }
        if (executor != IModuleMinimal(MODULE).executor()) {
            vm.skip(true); // EXECUTOR_PRIVATE_KEY must be module executor (EXECUTOR_ADDRESS)
            return;
        }
        // 1) Create Safe for a fresh address; call as owner (PRIVATE_KEY).
        uint256 safeOwnerKey = 1;
        address safeOwner = vm.addr(safeOwnerKey);
        vm.prank(owner);
        safeAddress = IFactoryMinimal(FACTORY).createSafeWallet(safeOwner);
        assertTrue(safeAddress != address(0), "safe created");

        // 2) Enable module on Safe: sign with Safe owner key (safeOwnerKey).
        bytes memory enableData = abi.encodeWithSignature("enableModule(address)", MODULE);
        uint256 nonce = ISafeMinimal(safeAddress).nonce();
        bytes32 txHash = ISafeMinimal(safeAddress).getTransactionHash(
            safeAddress, 0, enableData, 0, 0, 0, 0, address(0), address(0), nonce
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(safeOwnerKey, txHash);
        bytes memory signatures = abi.encodePacked(r, s, v);
        ok = ISafeMinimal(safeAddress).execTransaction(
            safeAddress, 0, enableData, 0, 0, 0, 0, address(0), address(0), signatures
        );
        require(ok, "enableModule tx failed");

        // 3) Set spending policy via a signed Safe tx (not via module: hook requires active policy, so we can't execTask setPolicy)
        uint64 deadline = uint64(block.timestamp + 1 days);
        uint256 spendLimitPerTx = 100 * 1e8;   // 100 USD, 8 decimals
        uint256 dailyLimitUsd = 1000 * 1e8;   // 1000 USD
        bytes memory setPolicyData = abi.encodeWithSignature(
            "setPolicy(uint64,uint256,uint256)",
            deadline,
            spendLimitPerTx,
            dailyLimitUsd
        );
        nonce = ISafeMinimal(safeAddress).nonce();
        txHash = ISafeMinimal(safeAddress).getTransactionHash(
            SPENDING_POLICY, 0, setPolicyData, 0, 0, 0, 0, address(0), address(0), nonce
        );
        (v, r, s) = vm.sign(safeOwnerKey, txHash);
        signatures = abi.encodePacked(r, s, v);
        ok = ISafeMinimal(safeAddress).execTransaction(
            SPENDING_POLICY, 0, setPolicyData, 0, 0, 0, 0, address(0), address(0), signatures
        );
        require(ok, "setPolicy Safe tx failed");

        // 4) ExecTask: Safe calls testContract.incrementBy(5) with declaredUsdValue = 1 USD (1e8)
        bytes memory incrementData = abi.encodeWithSignature("incrementBy(uint256)", 5);
        uint256 declaredUsd = 1e8; // 1 USD
        vm.prank(executor);
        ok = IModuleMinimal(MODULE).execTask(safeAddress, testContract, 0, incrementData, 0, declaredUsd);
        require(ok, "incrementBy execTask failed");

        // 5) Assert test contract state
        (bool succ, bytes memory countRet) = testContract.staticcall(abi.encodeWithSignature("getCount()"));
        require(succ, "getCount call failed");
        uint256 count = abi.decode(countRet, (uint256));
        assertEq(count, 5, "test contract count should be 5");
    }
}
