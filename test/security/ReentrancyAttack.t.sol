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
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pair } from "../../src/amm/Pair.sol";
import { IPairCallee } from "../../src/amm/IPairCallee.sol";
import { LPPositionNFT } from "../../src/tokens/LPPositionNFT.sol";
import { MockERC20 } from "../helpers/MockERC20.sol";

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

/// @dev Flash-swap callee that tries to re-enter Pair.swap during the callback.
///      Against the hardened Pair this must trip the ReentrancyGuard.
contract ReentrantSwapCallee is IPairCallee {
    Pair public pair;

    constructor(Pair _pair) {
        pair = _pair;
    }

    function pairCall(address, uint256 amount0, uint256, bytes calldata) external override {
        // Re-enter with empty data (no nested callback) — the guard reverts before any logic runs.
        pair.swap(amount0, 0, address(this), 0, "");
    }
}

/**
 * @notice FIXED-VERSION counterpart to the reentrancy case study.
 *         The production Pair.sol applies OpenZeppelin's `nonReentrant` to swap()
 *         and follows checks-effects-interactions, so a malicious flash-swap
 *         callee cannot re-enter to drain reserves.
 */
contract ReentrancyFixedTest is Test {
    Pair internal pair;
    MockERC20 internal token0;
    MockERC20 internal token1;
    LPPositionNFT internal lpNFT;

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    address internal admin = makeAddr("admin");

    function setUp() public {
        MockERC20 tA = new MockERC20("TokenA", "TA", 18);
        MockERC20 tB = new MockERC20("TokenB", "TB", 18);
        (token0, token1) = address(tA) < address(tB) ? (tA, tB) : (tB, tA);

        lpNFT = new LPPositionNFT(admin);
        pair = new Pair(address(token0), address(token1), address(lpNFT), admin);
        vm.prank(admin);
        lpNFT.grantRole(MINTER_ROLE, address(pair));

        // Seed liquidity: 100k / 100k.
        token0.mint(address(pair), 100_000e18);
        token1.mint(address(pair), 100_000e18);
        pair.mint(admin);
    }

    function test_fixed_reentrancyReverts() public {
        ReentrantSwapCallee attacker = new ReentrantSwapCallee(pair);

        // Outer flash swap (non-empty data triggers the callback, which re-enters).
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        pair.swap(1e18, 0, address(attacker), 0, hex"01");
    }
}
