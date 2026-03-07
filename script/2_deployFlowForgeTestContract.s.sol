// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FlowForgeTestContract} from "../src/FlowForgeTestContract.sol";

/**
 * @title DeployFlowForgeTestContract
 * @notice Deploys FlowForgeTestContract on the configured chain (e.g. Arbitrum Sepolia).
 * @dev Set PRIVATE_KEY and ARB_RPC_URL in .env. After deploy, add the contract address to deployments.json or test constants.
 */
contract DeployFlowForgeTestContract is Script {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address ownerAddress = vm.addr(deployerPrivateKey);
    string rpcUrl = vm.envString("ARB_RPC_URL");

    function run() public {
        vm.createSelectFork(rpcUrl);
        vm.startBroadcast(deployerPrivateKey);

        FlowForgeTestContract testContract = new FlowForgeTestContract();
        console.log("FlowForgeTestContract deployed at:", address(testContract));

        vm.stopBroadcast();
    }
}
