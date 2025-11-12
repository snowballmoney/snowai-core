// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Staking} from "src/Staking.sol";

contract DeployStaking is Script {
    function run() external returns (Staking staking) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address stakingToken = vm.envAddress("STAKING_TOKEN");
        address rewardsToken = vm.envAddress("STAKING_REWARDS_TOKEN");
        uint256 rewardRate = vm.envUint("STAKING_REWARD_RATE");

        vm.startBroadcast(deployerKey);
        Staking implementation = new Staking();
        bytes memory initData = abi.encodeWithSelector(
            Staking.initialize.selector,
            stakingToken,
            rewardsToken,
            rewardRate
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        staking = Staking(address(proxy));
        vm.stopBroadcast();
    }
}

