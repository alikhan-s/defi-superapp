// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Base64 } from "@openzeppelin/contracts/utils/Base64.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/// @title LPPositionNFT
/// @notice ERC-721 receipt token representing a liquidity position in an AMM pool.
/// @dev    Minting is restricted to addresses holding MINTER_ROLE (Pair contracts).
///         Token metadata is stored on-chain and returned as a base64-encoded JSON tokenURI.
contract LPPositionNFT is ERC721, AccessControl {
    using Strings for uint256;
    using Strings for address;

    // -------------------------------------------------------------------------
    // Roles
    // -------------------------------------------------------------------------

    /// @notice Role that allows minting and burning of position tokens.
    ///         Granted to AMM Pair contracts by the Factory during pool deployment.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    /// @dev On-chain metadata for each token.
    struct Position {
        address pool;
        uint256 liquidity;
        uint256 createdAt;
    }

    /// @dev Auto-incrementing token ID counter; starts at 1.
    uint256 private _nextTokenId;

    /// @dev tokenId → position data.
    mapping(uint256 => Position) private _positions;

    // -------------------------------------------------------------------------
    // Custom errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when the caller is neither the token owner nor a MINTER_ROLE holder.
    error NotAuthorized();

    /// @notice Thrown when querying a token that does not exist.
    error TokenDoesNotExist(uint256 tokenId);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @notice Deploy the LP Position NFT contract.
    /// @param admin  Address granted DEFAULT_ADMIN_ROLE (can grant/revoke MINTER_ROLE).
    constructor(address admin) ERC721("LP Position", "LPOS") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // Minting
    // -------------------------------------------------------------------------

    /// @notice Mint a new LP position token.
    /// @dev    Caller must hold MINTER_ROLE.  Position metadata is stored on-chain.
    /// @param to        Recipient of the minted token.
    /// @param pool      Address of the AMM pool this position belongs to.
    /// @param liquidity Liquidity units represented by this position.
    /// @return tokenId  The newly minted token ID.
    function mint(address to, address pool, uint256 liquidity)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 tokenId)
    {
        tokenId = ++_nextTokenId;
        _positions[tokenId] = Position({ pool: pool, liquidity: liquidity, createdAt: block.timestamp });
        _safeMint(to, tokenId);
    }

    // -------------------------------------------------------------------------
    // Burning
    // -------------------------------------------------------------------------

    /// @notice Burn a position token.
    /// @dev    Caller must be the token owner OR hold MINTER_ROLE.
    /// @param tokenId The token to burn.
    function burn(uint256 tokenId) external {
        if (!_exists(tokenId)) revert TokenDoesNotExist(tokenId);
        bool isMinter = hasRole(MINTER_ROLE, msg.sender);
        bool isOwner = ownerOf(tokenId) == msg.sender;
        if (!isMinter && !isOwner) revert NotAuthorized();
        delete _positions[tokenId];
        _burn(tokenId);
    }

    // -------------------------------------------------------------------------
    // Metadata
    // -------------------------------------------------------------------------

    /// @notice Return on-chain base64-encoded JSON metadata for `tokenId`.
    /// @param tokenId The token whose URI is requested.
    /// @return A data-URI string: `data:application/json;base64,<encoded JSON>`.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist(tokenId);
        Position memory pos = _positions[tokenId];

        string memory json = string.concat(
            '{"name":"LP Position #',
            tokenId.toString(),
            '","description":"DeFi Super-App liquidity position receipt","attributes":[',
            '{"trait_type":"Pool","value":"',
            Strings.toHexString(uint160(pos.pool), 20),
            '"},{"trait_type":"Liquidity","value":"',
            pos.liquidity.toString(),
            '"},{"trait_type":"Created At","value":"',
            pos.createdAt.toString(),
            '"}]}'
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    // -------------------------------------------------------------------------
    // Position getter
    // -------------------------------------------------------------------------

    /// @notice Return the stored position data for `tokenId`.
    /// @param tokenId The token to query.
    /// @return pool       Pool address for this position.
    /// @return liquidity  Liquidity units.
    /// @return createdAt  Block timestamp at mint time.
    function getPosition(uint256 tokenId) external view returns (address pool, uint256 liquidity, uint256 createdAt) {
        if (!_exists(tokenId)) revert TokenDoesNotExist(tokenId);
        Position memory pos = _positions[tokenId];
        return (pos.pool, pos.liquidity, pos.createdAt);
    }

    // -------------------------------------------------------------------------
    // Required overrides
    // -------------------------------------------------------------------------

    /// @dev Both ERC721 and AccessControl define supportsInterface; resolve the diamond.
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Returns true if `tokenId` has been minted and not yet burned.
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
}
