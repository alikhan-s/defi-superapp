pragma solidity ^0.8.24;

contract VulnerableTreasury {
    receive() external payable { }

    function withdrawETH(address to, uint256 amount) external {
        (bool success,) = to.call{ value: amount }("");
        require(success);
    }
}
