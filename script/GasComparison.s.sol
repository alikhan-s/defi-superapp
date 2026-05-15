// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Self-contained gas-comparison script. Run twice:
//   forge script script/GasComparison.s.sol --tc GasComparison --rpc-url http://localhost:8545
//   forge script script/GasComparison.s.sol --tc GasComparison --fork-url $ARBITRUM_SEPOLIA_RPC_URL
//
// Deploys minimal infra in the simulation (no broadcast), runs the 6 ops, and prints gas per op.
// Output lines are prefixed with "GASCOMP|" for easy grepping into the markdown table.

import { Script, console } from "forge-std/Script.sol";

import { GovernanceToken } from "../src/tokens/GovernanceToken.sol";
import { ChainlinkPriceOracle } from "../src/oracle/ChainlinkPriceOracle.sol";
import { MockAggregator } from "../src/oracle/MockAggregator.sol";
import { LPPositionNFT } from "../src/tokens/LPPositionNFT.sol";
import { PairFactory } from "../src/amm/PairFactory.sol";
import { Pair } from "../src/amm/Pair.sol";
import { LendingPool } from "../src/lending/LendingPool.sol";
import { YieldVault, ILendingPool } from "../src/vault/YieldVault.sol";
import { ProtocolTimelock } from "../src/governance/ProtocolTimelock.sol";
import { ProtocolGovernor } from "../src/governance/ProtocolGovernor.sol";

import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GasMockToken is ERC20 {
    uint8 private immutable _d;

    constructor(string memory n, string memory s, uint8 dec) ERC20(n, s) {
        _d = dec;
    }

    function decimals() public view override returns (uint8) {
        return _d;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract GasComparison is Script {
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");

    address internal actor;
    GasMockToken internal weth;
    GasMockToken internal usdc;
    Pair internal pair;
    LendingPool internal pool;
    YieldVault internal vault;
    uint256 internal lpTokenId;

    function run() external {
        // msg.sender in scripts is forge's configured sender; stable within the run.
        actor = msg.sender;

        _bootstrap();
        _measureAmm();
        _measureVaultAndBorrow();
        _measureVote();
    }

    function _bootstrap() internal {
        weth = new GasMockToken("WETH", "WETH", 18);
        usdc = new GasMockToken("USDC", "USDC", 6);

        MockAggregator wethFeed = new MockAggregator(2000 * 1e8, 8);
        MockAggregator usdcFeed = new MockAggregator(1 * 1e8, 8);

        // Grant admin to actor so subsequent role-gated calls succeed under their pranked sender.
        ChainlinkPriceOracle oracle = new ChainlinkPriceOracle(actor);
        vm.prank(actor);
        oracle.addFeed(address(weth), address(wethFeed), 86_400);
        vm.prank(actor);
        oracle.addFeed(address(usdc), address(usdcFeed), 86_400);

        LPPositionNFT lpNFT = new LPPositionNFT(actor);
        PairFactory factory = new PairFactory(address(lpNFT), actor);
        // Factory needs DEFAULT_ADMIN_ROLE on lpNFT so it can grant MINTER_ROLE to each new pair.
        vm.prank(actor);
        lpNFT.grantRole(bytes32(0), address(factory));
        pair = Pair(factory.createPair(address(weth), address(usdc)));

        pool = new LendingPool(address(weth), address(usdc), address(oracle), 8000, 1000, 100, 1000, actor);
        vault = new YieldVault(IERC20(address(usdc)), ILendingPool(address(pool)), "yv-USDC", "yvUSDC", actor);

        weth.mint(actor, 1_000_000 ether);
        usdc.mint(actor, 10_000_000 * 1e6);
    }

    function _measureAmm() internal {
        // OP 1: add liquidity
        vm.prank(actor);
        weth.transfer(address(pair), 100_000 ether);
        vm.prank(actor);
        usdc.transfer(address(pair), 100_000 * 1e6);
        uint256 g = gasleft();
        vm.prank(actor);
        (, uint256 tokenId) = pair.mint(actor);
        _emit("addLiquidity", g - gasleft());
        lpTokenId = tokenId;

        // OP 2: swap (WETH -> USDC)
        vm.prank(actor);
        weth.transfer(address(pair), 100 ether);
        uint256 expectedOut = _quoteSwap(100 ether);
        bool wethIsToken0 = pair.token0() == address(weth);
        g = gasleft();
        vm.prank(actor);
        if (wethIsToken0) {
            pair.swap(0, expectedOut, actor, 0, "");
        } else {
            pair.swap(expectedOut, 0, actor, 0, "");
        }
        _emit("swap", g - gasleft());

        // OP 3: remove liquidity
        g = gasleft();
        vm.prank(actor);
        pair.burn(lpTokenId, actor);
        _emit("removeLiquidity", g - gasleft());
    }

    function _quoteSwap(uint256 amountIn) internal view returns (uint256) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        bool wethIsToken0 = pair.token0() == address(weth);
        uint256 amtInFee = amountIn * 997;
        return wethIsToken0
            ? (amtInFee * uint256(r1)) / (uint256(r0) * 1000 + amtInFee)
            : (amtInFee * uint256(r0)) / (uint256(r1) * 1000 + amtInFee);
    }

    function _measureVaultAndBorrow() internal {
        // OP 4: vault deposit
        usdc.mint(actor, 1_000_000 * 1e6);
        vm.prank(actor);
        usdc.approve(address(vault), type(uint256).max);
        uint256 g = gasleft();
        vm.prank(actor);
        vault.deposit(10_000 * 1e6, actor);
        _emit("vaultDeposit", g - gasleft());

        // OP 5: borrow
        vm.prank(actor);
        weth.approve(address(pool), type(uint256).max);
        vm.prank(actor);
        pool.depositCollateral(100 ether);
        g = gasleft();
        vm.prank(actor);
        pool.borrow(5000 * 1e6);
        _emit("borrow", g - gasleft());
    }

    function _measureVote() internal {
        GovernanceToken gov = new GovernanceToken("Gov", "GOV", 10_000_000 ether, actor);
        vm.prank(actor);
        gov.delegate(actor);

        address[] memory empty = new address[](0);
        ProtocolTimelock timelock = new ProtocolTimelock(2 days, empty, empty, actor);
        ProtocolGovernor governor = new ProtocolGovernor(IVotes(address(gov)), timelock);

        address[] memory targets = new address[](1);
        targets[0] = address(0xDeaD);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.roll(block.number + 1);
        vm.prank(actor);
        uint256 propId = governor.propose(targets, values, calldatas, "gas-comp");
        vm.roll(block.number + governor.votingDelay() + 1);

        uint256 g = gasleft();
        vm.prank(actor);
        governor.castVote(propId, 1);
        _emit("vote", g - gasleft());
    }

    function _emit(string memory op, uint256 gasUsed) internal pure {
        console.log(string.concat("GASCOMP_DEBUG | Op: ", op, " | Units: "), gasUsed);
    }
}
