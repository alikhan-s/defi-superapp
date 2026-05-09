// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { LPPositionNFT } from "../tokens/LPPositionNFT.sol";
import { IPairCallee } from "./IPairCallee.sol";

/// @title Pair
/// @notice Uniswap V2-style constant-product AMM.  Liquidity positions are
///         represented as ERC-721 tokens minted by the embedded LPPositionNFT.
/// @dev    Packed-reserve slot mirrors the Uniswap V2 layout (uint112, uint112, uint32).
///         All state-mutating paths follow CEI ordering and are guarded by
///         ReentrancyGuard.  Circuit-breaker pause is available via PAUSER_ROLE.
contract Pair is ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Roles / constants
    // -------------------------------------------------------------------------

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Minimum liquidity permanently locked on the first mint to prevent
    ///         the constant-product from being fully drained.
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    address public immutable token0;
    address public immutable token1;
    LPPositionNFT public immutable lpNFT;

    // -------------------------------------------------------------------------
    // Packed reserves  (mirrors Uniswap V2 slot layout)
    // -------------------------------------------------------------------------

    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32 private _blockTimestampLast;

    // -------------------------------------------------------------------------
    // LP accounting
    // -------------------------------------------------------------------------

    /// @notice Total liquidity supply including the permanently locked portion.
    uint256 public totalLPSupply;

    /// @notice Liquidity locked on the first mint (equals MINIMUM_LIQUIDITY after first mint, 0 before).
    uint256 public lockedLiquidity;

    /// @notice Maps an LP NFT token ID to the liquidity units it represents.
    mapping(uint256 tokenId => uint256) public liquidityOf;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Mint(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity, uint256 tokenId);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to, uint256 tokenId);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    // -------------------------------------------------------------------------
    // Custom errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when minted or returned liquidity would be zero.
    error InsufficientLiquidity();

    /// @notice Thrown when both output amounts of a swap are zero.
    error InsufficientOutput();

    /// @notice Thrown when the K invariant check fails after a swap.
    error K();

    /// @notice Thrown when a balance exceeds the uint112 reserve cap.
    error Locked();

    /// @notice Thrown when the received output is below the caller's slippage floor.
    error Slippage();

    /// @notice Thrown when a zero address is supplied for a required parameter.
    error ZeroAddress();

    /// @notice Thrown when the caller is not the NFT owner or an approved operator.
    error Forbidden();

    /// @notice Thrown when `to` in swap equals one of the pair's token addresses.
    error InvalidToken();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address token0_, address token1_, address lpNFT_, address admin) {
        if (token0_ == address(0) || token1_ == address(0) || lpNFT_ == address(0) || admin == address(0)) {
            revert ZeroAddress();
        }
        token0 = token0_;
        token1 = token1_;
        lpNFT = LPPositionNFT(lpNFT_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    // -------------------------------------------------------------------------
    // Liquidity — mint
    // -------------------------------------------------------------------------

    /// @notice Deposit token0 and token1 and receive an LP NFT representing the position.
    /// @dev    Caller must transfer both tokens to this contract before calling `mint`.
    ///         On the very first mint MINIMUM_LIQUIDITY units are permanently locked.
    /// @param to  Recipient of the newly minted LP NFT.
    /// @return liquidity  Liquidity units credited to the new NFT.
    /// @return tokenId    The minted LP NFT token ID.
    function mint(address to) external nonReentrant whenNotPaused returns (uint256 liquidity, uint256 tokenId) {
        if (to == address(0)) revert ZeroAddress();

        uint112 reserve0 = _reserve0;
        uint112 reserve1 = _reserve1;
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        uint256 _totalLPSupply = totalLPSupply;

        if (_totalLPSupply == 0) {
            // First mint: lock MINIMUM_LIQUIDITY permanently.
            uint256 raw = Math.sqrt(amount0 * amount1);
            if (raw <= MINIMUM_LIQUIDITY) revert InsufficientLiquidity();
            liquidity = raw - MINIMUM_LIQUIDITY;
            lockedLiquidity = MINIMUM_LIQUIDITY;
            totalLPSupply = raw; // raw = liquidity + MINIMUM_LIQUIDITY
        } else {
            // Subsequent mints: proportional to existing supply.
            liquidity = Math.min((amount0 * _totalLPSupply) / reserve0, (amount1 * _totalLPSupply) / reserve1);
            totalLPSupply = _totalLPSupply + liquidity;
        }

        if (liquidity == 0) revert InsufficientLiquidity();

        tokenId = lpNFT.mint(to, address(this), liquidity);
        liquidityOf[tokenId] = liquidity;

        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1, liquidity, tokenId);
    }

    // -------------------------------------------------------------------------
    // Liquidity — burn
    // -------------------------------------------------------------------------

    /// @notice Burn an LP NFT and receive proportional token0/token1 back.
    /// @dev    Caller must be the NFT owner or an approved operator.
    /// @param tokenId  The LP NFT to burn.
    /// @param to       Recipient of the withdrawn tokens.
    /// @return amount0  token0 returned.
    /// @return amount1  token1 returned.
    function burn(uint256 tokenId, address to)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amount0, uint256 amount1)
    {
        if (to == address(0)) revert ZeroAddress();

        // --- Checks ---
        address owner = lpNFT.ownerOf(tokenId);
        if (
            owner != msg.sender && lpNFT.getApproved(tokenId) != msg.sender
                && !lpNFT.isApprovedForAll(owner, msg.sender)
        ) revert Forbidden();

        uint256 liquidity = liquidityOf[tokenId];
        if (liquidity == 0) revert InsufficientLiquidity();

        uint256 _totalLPSupply = totalLPSupply;
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        amount0 = (liquidity * balance0) / _totalLPSupply;
        amount1 = (liquidity * balance1) / _totalLPSupply;
        if (amount0 == 0 && amount1 == 0) revert InsufficientLiquidity();

        // --- Effects ---
        liquidityOf[tokenId] = 0;
        totalLPSupply = _totalLPSupply - liquidity;

        // --- Interactions ---
        lpNFT.burn(tokenId);
        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1);

        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
        emit Burn(msg.sender, amount0, amount1, to, tokenId);
    }

    // -------------------------------------------------------------------------
    // Swap
    // -------------------------------------------------------------------------

    /// @notice Swap tokens against the pair's reserves.
    ///         For flash swaps, pass non-empty `data`; the pair optimistically
    ///         transfers output tokens first, then calls
    ///         `IPairCallee(to).pairCall(...)` before verifying the K invariant.
    /// @param amount0Out  token0 to send to `to`.
    /// @param amount1Out  token1 to send to `to`.
    /// @param to          Recipient of the output tokens (and flash-swap callee).
    /// @param minOut      Slippage floor: reverts if amount0Out + amount1Out < minOut.
    /// @param data        Arbitrary bytes forwarded to the flash-swap callee.
    function swap(uint256 amount0Out, uint256 amount1Out, address to, uint256 minOut, bytes calldata data)
        external
        nonReentrant
        whenNotPaused
    {
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutput();
        if (to == address(0)) revert ZeroAddress();
        if (to == token0 || to == token1) revert InvalidToken();

        uint112 reserve0 = _reserve0;
        uint112 reserve1 = _reserve1;

        if (amount0Out >= reserve0 || amount1Out >= reserve1) revert InsufficientLiquidity();
        if (amount0Out + amount1Out < minOut) revert Slippage();

        // Optimistic transfer
        if (amount0Out > 0) IERC20(token0).safeTransfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).safeTransfer(to, amount1Out);

        // Flash-swap callback (optional)
        if (data.length > 0) IPairCallee(to).pairCall(msg.sender, amount0Out, amount1Out, data);

        // Verify K invariant, update reserves, emit — done in a helper to avoid
        // stack-too-deep when combined with the many parameters above.
        (uint256 amount0In, uint256 amount1In) = _settleSwap(reserve0, reserve1, amount0Out, amount1Out);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @dev Reads post-swap balances, checks the K invariant with 0.3% fee, and
    ///      updates the packed reserve slot.  Returns the inferred input amounts.
    function _settleSwap(uint112 reserve0, uint112 reserve1, uint256 amount0Out, uint256 amount1Out)
        private
        returns (uint256 amount0In, uint256 amount1In)
    {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        amount0In = balance0 > uint256(reserve0) - amount0Out ? balance0 - (uint256(reserve0) - amount0Out) : 0;
        amount1In = balance1 > uint256(reserve1) - amount1Out ? balance1 - (uint256(reserve1) - amount1Out) : 0;

        if (amount0In == 0 && amount1In == 0) revert InsufficientOutput();

        // K invariant: (b0·1000 − amtIn0·3) · (b1·1000 − amtIn1·3) ≥ r0·r1·1_000_000
        // Overflow safety: reserves ≤ uint112 max; both products fit in uint256.
        uint256 b0Adj = balance0 * 1000 - amount0In * 3;
        uint256 b1Adj = balance1 * 1000 - amount1In * 3;
        if (b0Adj * b1Adj < uint256(reserve0) * uint256(reserve1) * 1_000_000) revert K();

        _update(balance0, balance1);
    }

    // -------------------------------------------------------------------------
    // Reserve management
    // -------------------------------------------------------------------------

    /// @notice Transfer any tokens held above the current reserves to `to`.
    function skim(address to) external nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        uint256 excess0 = IERC20(token0).balanceOf(address(this)) - _reserve0;
        uint256 excess1 = IERC20(token1).balanceOf(address(this)) - _reserve1;
        if (excess0 > 0) IERC20(token0).safeTransfer(to, excess0);
        if (excess1 > 0) IERC20(token1).safeTransfer(to, excess1);
    }

    /// @notice Sync reserves to match the current token balances.
    function sync() external nonReentrant {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
    }

    // -------------------------------------------------------------------------
    // Circuit breaker
    // -------------------------------------------------------------------------

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _update(uint256 balance0, uint256 balance1) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert Locked();
        _reserve0 = uint112(balance0);
        _reserve1 = uint112(balance1);
        _blockTimestampLast = uint32(block.timestamp);
        emit Sync(_reserve0, _reserve1);
    }
}
