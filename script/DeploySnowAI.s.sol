// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {SnowAI} from "src/SnowAI.sol";

contract DeploySnowAI is Script {
    function run() external returns (SnowAI token) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address treasury = vm.envAddress("SNOWAI_TREASURY");
        uint256 initialSupply = vm.envUint("SNOWAI_INITIAL_SUPPLY");

        vm.startBroadcast(deployerKey);
        token = new SnowAI(treasury, initialSupply);
        vm.stopBroadcast();
    }
}

