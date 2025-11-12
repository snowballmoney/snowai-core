// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TokenVesting} from "src/TokenVesting.sol";

contract DeployTokenVesting is Script {
    function run() external returns (TokenVesting vesting) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address token = vm.envAddress("VESTING_TOKEN");

        vm.startBroadcast(deployerKey);
        vesting = new TokenVesting(IERC20(token));
        vm.stopBroadcast();
    }
}

