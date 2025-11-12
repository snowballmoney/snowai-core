// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {SnowAI} from "src/SnowAI.sol";

contract SnowAITokenTest is Test {
    address private constant TREASURY = address(0xBEEF);

    function testConstructorMintsToTreasury() public {
        uint256 initialSupply = 1_000 ether;
        SnowAI token = new SnowAI(TREASURY, initialSupply);

        assertEq(token.name(), "SnowAI");
        assertEq(token.symbol(), "SAI");
        assertEq(token.totalSupply(), initialSupply);
        assertEq(token.balanceOf(TREASURY), initialSupply);
        assertEq(token.owner(), address(this));
    }

    function testConstructorZeroTreasuryReverts() public {
        vm.expectRevert("SnowAI: treasury zero address");
        new SnowAI(address(0), 1);
    }

    function testBurnReducesSupply() public {
        SnowAI token = new SnowAI(address(this), 100 ether);

        token.burn(40 ether);

        assertEq(token.totalSupply(), 60 ether);
        assertEq(token.balanceOf(address(this)), 60 ether);
    }
}

