// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CREATE3} from "../lib/solady/src/utils/CREATE3.sol";
import {FlowForgeSafeFactory} from "../src/FlowForgeSafeFactory.sol";
import {FlowForgeSafeModule} from "../src/FlowForgeSafeModule.sol";
import {FlowForgeSpendingPolicy} from "../src/FlowForgeSpendingPolicy.sol";

/**
 * @title DeployFlowForgeSafeContractsL1
 * @notice Deploy FlowForgeSafeFactory and FlowForgeSafeModule and FlowForgeSpendingPolicy on L1 using CREATE3
 * @dev PRIVATE_KEY = deployer (owner). EXECUTOR_ADDRESS = relayer (createSafeWallet + execTask).
 */
contract DeployFlowForgeSafeContractsL1 is Script {
    address ethSafeProxyFactory = vm.envAddress("ETH_SAFE_PROXY_FACTORY");
    address ethSafeSingleton = vm.envAddress("ETH_SAFE_SINGLETON");
    address executorAddress = vm.envAddress("EXECUTOR_ADDRESS");

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address ownerAddress = vm.addr(deployerPrivateKey);
    string rpcUrl = vm.envString("ETH_RPC_URL");

    bytes32 constant FACTORY_SALT = keccak256("FlowForgeSafeFactory_v1_3");
    bytes32 constant MODULE_SALT = keccak256("FlowForgeSafeModule_v1_2");
    bytes32 constant SPENDING_POLICY_SALT = keccak256("FlowForgeSpendingPolicy_v1_2");

    function run() public {
        vm.createSelectFork(rpcUrl);
        vm.startBroadcast(deployerPrivateKey);

        bytes memory factoryBytecode = abi.encodePacked(
            type(FlowForgeSafeFactory).creationCode,
            abi.encode(ethSafeProxyFactory, ethSafeSingleton, ownerAddress, executorAddress)
        );
        address factory = CREATE3.deployDeterministic(factoryBytecode, FACTORY_SALT);

        bytes memory moduleBytecode = abi.encodePacked(
            type(FlowForgeSafeModule).creationCode,
            abi.encode(executorAddress, ownerAddress)
        );
        address module = CREATE3.deployDeterministic(moduleBytecode, MODULE_SALT);

        bytes memory policyBytecode = abi.encodePacked(
            type(FlowForgeSpendingPolicy).creationCode
        );
        address policy = CREATE3.deployDeterministic(policyBytecode, SPENDING_POLICY_SALT);

        FlowForgeSafeModule(module).setHook(policy);

        vm.stopBroadcast();
        console.log("FlowForgeSafeFactory deployed at:", factory);
        console.log("FlowForgeSafeModule deployed at:", module);
        console.log("FlowForgeSpendingPolicy deployed at:", policy);
    }
}

/**
 * @title DeployFlowForgeSafeContractsL2
 * @notice Deploy FlowForgeSafeFactory and FlowForgeSafeModule and FlowForgeSpendingPolicy on L2 using CREATE3
 * @dev PRIVATE_KEY = deployer (owner). EXECUTOR_ADDRESS = relayer (createSafeWallet + execTask).
 */
contract DeployFlowForgeSafeContractsL2 is Script {
    address arbSafeProxyFactory = vm.envAddress("ARB_SAFE_PROXY_FACTORY");
    address arbSafeSingleton = vm.envAddress("ARB_SAFE_SINGLETON");
    address executorAddress = vm.envAddress("EXECUTOR_ADDRESS");

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address ownerAddress = vm.addr(deployerPrivateKey);
    string rpcUrl = vm.envString("ARB_RPC_URL");

    bytes32 constant FACTORY_SALT = keccak256("FlowForgeSafeFactory_v1_3");
    bytes32 constant MODULE_SALT = keccak256("FlowForgeSafeModule_v1_2");
    bytes32 constant SPENDING_POLICY_SALT = keccak256("FlowForgeSpendingPolicy_v1_2");

    function run() public {
        vm.createSelectFork(rpcUrl);
        vm.startBroadcast(deployerPrivateKey);

        bytes memory factoryBytecode = abi.encodePacked(
            type(FlowForgeSafeFactory).creationCode,
            abi.encode(arbSafeProxyFactory, arbSafeSingleton, ownerAddress, executorAddress)
        );
        address factory = CREATE3.deployDeterministic(factoryBytecode, FACTORY_SALT);

        bytes memory moduleBytecode = abi.encodePacked(
            type(FlowForgeSafeModule).creationCode,
            abi.encode(executorAddress, ownerAddress)
        );
        address module = CREATE3.deployDeterministic(moduleBytecode, MODULE_SALT);

        bytes memory policyBytecode = abi.encodePacked(
            type(FlowForgeSpendingPolicy).creationCode
        );
        address policy = CREATE3.deployDeterministic(policyBytecode, SPENDING_POLICY_SALT);

        FlowForgeSafeModule(module).setHook(policy);

        vm.stopBroadcast();
        console.log("FlowForgeSafeFactory deployed at:", factory);
        console.log("FlowForgeSafeModule deployed at:", module);
        console.log("FlowForgeSpendingPolicy deployed at:", policy);
    }
}

contract DeployFlowForgeSafeContracts is Script {
    function run() public {
        DeployFlowForgeSafeContractsL1 l1 = new DeployFlowForgeSafeContractsL1();
        DeployFlowForgeSafeContractsL2 l2 = new DeployFlowForgeSafeContractsL2();
        l1.run();
        l2.run();
    }
}
