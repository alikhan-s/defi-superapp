// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { LPPositionNFT } from "../tokens/LPPositionNFT.sol";
import { Pair } from "./Pair.sol";

/// @title PairFactory
/// @notice Deploys Pair contracts and wires them to the shared LPPositionNFT.
/// @dev    Supports both vanilla CREATE (deterministic only by nonce) and CREATE2
///         (deterministic by salt).  For every new pair the factory grants
///         MINTER_ROLE on LPPositionNFT, so it must hold DEFAULT_ADMIN_ROLE on
///         that contract before any pair is created.
///
///         Token pairs are always stored sorted (token0 < token1) so the
///         bidirectional lookup `getPair[A][B] == getPair[B][A]` holds.
contract PairFactory is AccessControl {
    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    LPPositionNFT public immutable lpNFT;

    /// @notice Admin address granted to every newly deployed Pair.
    address public immutable pairAdmin;

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    /// @notice Maps (token0, token1) → pair address (sorted, token0 < token1).
    mapping(address => mapping(address => address)) public getPair;

    /// @notice Ordered list of all deployed pair addresses.
    address[] public allPairs;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @param token0        Lower-address token of the pair.
    /// @param token1        Higher-address token of the pair.
    /// @param pair          Deployed Pair address.
    /// @param count         New length of `allPairs` after this deployment.
    /// @param deterministic True when the pair was deployed with CREATE2.
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 count, bool deterministic);

    // -------------------------------------------------------------------------
    // Custom errors
    // -------------------------------------------------------------------------

    error PairExists();
    error IdenticalTokens();
    error ZeroAddress();
    error Create2Failed();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address lpNFT_, address admin) {
        if (lpNFT_ == address(0) || admin == address(0)) revert ZeroAddress();
        lpNFT = LPPositionNFT(lpNFT_);
        pairAdmin = admin;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // Pair creation — CREATE
    // -------------------------------------------------------------------------

    /// @notice Deploy a Pair for `tokenA`/`tokenB` using regular CREATE.
    /// @dev    Reverts if a pair for this token combination already exists.
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        if (getPair[token0][token1] != address(0)) revert PairExists();

        pair = address(new Pair(token0, token1, address(lpNFT), pairAdmin));
        _register(token0, token1, pair, false);
    }

    // -------------------------------------------------------------------------
    // Pair creation — CREATE2
    // -------------------------------------------------------------------------

    /// @notice Deploy a Pair for `tokenA`/`tokenB` using CREATE2 with `salt`.
    /// @dev    Allows off-chain pre-computation of the pair address via
    ///         `computePairAddress`.  Reverts if a pair already exists or
    ///         the CREATE2 deployment fails.
    function createPairDeterministic(address tokenA, address tokenB, bytes32 salt) external returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        if (getPair[token0][token1] != address(0)) revert PairExists();

        bytes memory initCode =
            abi.encodePacked(type(Pair).creationCode, abi.encode(token0, token1, address(lpNFT), pairAdmin));

        assembly {
            pair := create2(0, add(initCode, 32), mload(initCode), salt)
        }
        if (pair == address(0)) revert Create2Failed();

        _register(token0, token1, pair, true);
    }

    // -------------------------------------------------------------------------
    // Address prediction
    // -------------------------------------------------------------------------

    /// @notice Compute the address that `createPairDeterministic` would deploy
    ///         for `tokenA`/`tokenB` with `salt` — without actually deploying.
    function computePairAddress(address tokenA, address tokenB, bytes32 salt) external view returns (address) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(Pair).creationCode, abi.encode(token0, token1, address(lpNFT), pairAdmin))
        );
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert IdenticalTokens();
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function _register(address token0, address token1, address pair, bool deterministic) internal {
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        // Grant MINTER_ROLE on the shared NFT contract to the new pair.
        // Requires this factory to hold DEFAULT_ADMIN_ROLE on lpNFT.
        lpNFT.grantRole(keccak256("MINTER_ROLE"), pair);

        emit PairCreated(token0, token1, pair, allPairs.length, deterministic);
    }
}
