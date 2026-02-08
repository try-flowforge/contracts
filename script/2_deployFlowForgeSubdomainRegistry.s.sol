// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FlowForgeSubdomainRegistry} from "../src/FlowForgeSubdomainRegistry.sol";
import {FlowForgeEthUsdcPricer} from "../src/FlowForgeEthUsdcPricer.sol";

/**
 * @title DeployFlowForgeEnsRegistryAndPricer
 * @notice Deploy FlowForgeSubdomainRegistry and FlowForgeEthUsdcPricer on Ethereum in one go.
 *        Requires ENS_NAME_WRAPPER, USDC_ADDRESS, CHAINLINK_ETH_USD_FEED, ETH_RPC_URL in .env.
 *        After deploy: parent owner calls NameWrapper.setApprovalForAll(registry, true),
 *        then registry.setupDomain(parentNode, pricer, beneficiary, true).
 *        Users: registerWithToken(..., address(0)) for ETH, registerWithToken(..., USDC) for USDC.
 */
contract DeployFlowForgeEnsRegistryAndPricer is Script {
    function run() public {
        address nameWrapper = vm.envAddress("ENS_NAME_WRAPPER");
        address usdc = vm.envAddress("USDC_ADDRESS");
        address ethUsdFeed = vm.envAddress("CHAINLINK_ETH_USD_FEED");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory rpcUrl = vm.envString("ETH_RPC_URL");
        vm.createSelectFork(rpcUrl);
        vm.startBroadcast(deployerPrivateKey);

        FlowForgeSubdomainRegistry registry =
            new FlowForgeSubdomainRegistry(nameWrapper, usdc, ethUsdFeed);
        console.log("FlowForgeSubdomainRegistry deployed at:", address(registry));

        FlowForgeEthUsdcPricer pricer = new FlowForgeEthUsdcPricer(usdc, ethUsdFeed);
        console.log("FlowForgeEthUsdcPricer deployed at:", address(pricer));

        vm.stopBroadcast();
    }
}
