// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SnowAI Token
 * @notice ERC20 token with burn functionality that mints its initial supply to a treasury on deployment.
 */
contract SnowAI is ERC20Burnable, Ownable {
    /**
     * @notice Deploys the SnowAI token and mints the `initialSupply` to the provided `treasury`.
     * @param treasury Address that receives the initial token supply.
     * @param initialSupply Amount of tokens to mint to the treasury, expressed in wei units.
     */
    constructor(address treasury, uint256 initialSupply) Ownable(msg.sender) ERC20("SnowAI", "SAI") {
        require(treasury != address(0), "SnowAI: treasury zero address");
        if (initialSupply > 0) {
            _mint(treasury, initialSupply);
        }
    }
}