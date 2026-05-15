// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VulnerablePair {
    IERC20 public token0;
    uint256 public reserve0;

    constructor(address _token0) {
        token0 = IERC20(_token0);
    }

    function deposit(uint256 amount) external {
        token0.transferFrom(msg.sender, address(this), amount);
        reserve0 += amount;
    }

    function swap(uint256 amountOut, address to) external {
        token0.transfer(to, amountOut);
        reserve0 = token0.balanceOf(address(this));
    }
}
