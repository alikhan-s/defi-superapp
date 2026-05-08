// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { LPPositionNFT } from "../../src/tokens/LPPositionNFT.sol";

contract LPPositionNFTTest is Test {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    LPPositionNFT internal nft;

    // Cache the role constant so vm.prank isn't consumed by an external view call.
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal pool = makeAddr("pool");

    uint256 internal constant LIQUIDITY = 1000e18;

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        nft = new LPPositionNFT(admin);

        vm.prank(admin);
        nft.grantRole(MINTER_ROLE, minter);
    }

    // -------------------------------------------------------------------------
    // 1. Role gating on mint
    // -------------------------------------------------------------------------

    function test_mint_onlyMinterRole() public {
        vm.prank(alice);
        vm.expectRevert();
        nft.mint(alice, pool, LIQUIDITY);
    }

    function test_mint_minterCanMint() public {
        vm.prank(minter);
        uint256 id = nft.mint(alice, pool, LIQUIDITY);

        assertEq(id, 1);
        assertEq(nft.ownerOf(1), alice);
    }

    // -------------------------------------------------------------------------
    // 2. Metadata stored correctly
    // -------------------------------------------------------------------------

    function test_mint_storesPosition() public {
        vm.prank(minter);
        nft.mint(alice, pool, LIQUIDITY);

        (address storedPool, uint256 storedLiquidity, uint256 createdAt) = nft.getPosition(1);

        assertEq(storedPool, pool);
        assertEq(storedLiquidity, LIQUIDITY);
        assertEq(createdAt, block.timestamp);
    }

    // -------------------------------------------------------------------------
    // 3. tokenURI – base64 JSON
    // -------------------------------------------------------------------------

    function test_tokenURI_validBase64JSON() public {
        vm.prank(minter);
        nft.mint(alice, pool, LIQUIDITY);

        string memory uri = nft.tokenURI(1);

        // Must start with the data-URI prefix
        assertTrue(_startsWith(uri, "data:application/json;base64,"), "URI prefix mismatch");

        // Strip prefix and decode
        bytes memory decoded = _base64Decode(_slice(uri, 29));

        // Decoded payload must contain expected fields
        string memory json = string(decoded);
        assertTrue(_contains(json, '"name":"LP Position #1"'), "name field missing");
        assertTrue(_contains(json, '"trait_type":"Pool"'), "Pool trait missing");
        assertTrue(_contains(json, '"trait_type":"Liquidity"'), "Liquidity trait missing");
        assertTrue(_contains(json, '"trait_type":"Created At"'), "CreatedAt trait missing");
    }

    function test_tokenURI_nonExistentReverts() public {
        vm.expectRevert(abi.encodeWithSelector(LPPositionNFT.TokenDoesNotExist.selector, 99));
        nft.tokenURI(99);
    }

    // -------------------------------------------------------------------------
    // 4. Transfer retains metadata
    // -------------------------------------------------------------------------

    function test_transfer_retainsMetadata() public {
        vm.prank(minter);
        nft.mint(alice, pool, LIQUIDITY);

        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);

        assertEq(nft.ownerOf(1), bob);

        (address storedPool, uint256 storedLiquidity,) = nft.getPosition(1);
        assertEq(storedPool, pool);
        assertEq(storedLiquidity, LIQUIDITY);
    }

    // -------------------------------------------------------------------------
    // 5. Burn by owner
    // -------------------------------------------------------------------------

    function test_burn_ownerCanBurn() public {
        vm.prank(minter);
        nft.mint(alice, pool, LIQUIDITY);

        vm.prank(alice);
        nft.burn(1);

        vm.expectRevert();
        nft.ownerOf(1);
    }

    // -------------------------------------------------------------------------
    // 6. Burn by minter
    // -------------------------------------------------------------------------

    function test_burn_minterCanBurn() public {
        vm.prank(minter);
        nft.mint(alice, pool, LIQUIDITY);

        vm.prank(minter);
        nft.burn(1);

        vm.expectRevert();
        nft.ownerOf(1);
    }

    // -------------------------------------------------------------------------
    // 7. Burn by unauthorised address
    // -------------------------------------------------------------------------

    function test_burn_nonOwnerNonMinterReverts() public {
        vm.prank(minter);
        nft.mint(alice, pool, LIQUIDITY);

        vm.prank(bob);
        vm.expectRevert(LPPositionNFT.NotAuthorized.selector);
        nft.burn(1);
    }

    // -------------------------------------------------------------------------
    // 8. Role grant / revoke by admin
    // -------------------------------------------------------------------------

    function test_grantRole_newMinterCanMint() public {
        vm.prank(admin);
        nft.grantRole(MINTER_ROLE, carol);

        vm.prank(carol);
        uint256 id = nft.mint(alice, pool, LIQUIDITY);
        assertEq(id, 1);
    }

    function test_revokeRole_revokedMinterCannotMint() public {
        vm.prank(admin);
        nft.revokeRole(MINTER_ROLE, minter);

        vm.prank(minter);
        vm.expectRevert();
        nft.mint(alice, pool, LIQUIDITY);
    }

    function test_nonAdmin_cannotGrantRole() public {
        vm.prank(alice);
        vm.expectRevert();
        nft.grantRole(MINTER_ROLE, bob);
    }

    // -------------------------------------------------------------------------
    // 9. getPosition on non-existent token reverts
    // -------------------------------------------------------------------------

    function test_getPosition_nonExistentReverts() public {
        vm.expectRevert(abi.encodeWithSelector(LPPositionNFT.TokenDoesNotExist.selector, 42));
        nft.getPosition(42);
    }

    // -------------------------------------------------------------------------
    // 10. Token IDs auto-increment
    // -------------------------------------------------------------------------

    function test_tokenIds_autoIncrement() public {
        vm.startPrank(minter);
        uint256 id1 = nft.mint(alice, pool, LIQUIDITY);
        uint256 id2 = nft.mint(bob, pool, LIQUIDITY);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    address internal carol = makeAddr("carol");

    function _startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory s = bytes(str);
        bytes memory p = bytes(prefix);
        if (s.length < p.length) return false;
        for (uint256 i; i < p.length; i++) {
            if (s[i] != p[i]) return false;
        }
        return true;
    }

    function _contains(string memory str, string memory sub) internal pure returns (bool) {
        bytes memory s = bytes(str);
        bytes memory b = bytes(sub);
        if (b.length > s.length) return false;
        for (uint256 i; i <= s.length - b.length; i++) {
            bool found = true;
            for (uint256 j; j < b.length; j++) {
                if (s[i + j] != b[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    /// @dev Slice a string from index `start` to the end (no bounds check needed here).
    function _slice(string memory str, uint256 start) internal pure returns (string memory) {
        bytes memory s = bytes(str);
        bytes memory result = new bytes(s.length - start);
        for (uint256 i; i < result.length; i++) {
            result[i] = s[start + i];
        }
        return string(result);
    }

    /// @dev Minimal base64 decoder for test assertions (standard alphabet, with padding).
    function _base64Decode(string memory encoded) internal pure returns (bytes memory) {
        bytes memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

        bytes memory data = bytes(encoded);
        uint256 len = data.length;
        require(len % 4 == 0, "invalid base64 length");

        // Count trailing '=' padding
        uint256 padding = 0;
        if (len > 0 && data[len - 1] == "=") padding++;
        if (len > 1 && data[len - 2] == "=") padding++;

        bytes memory decoded = new bytes((len / 4) * 3 - padding);

        uint256 j;
        for (uint256 i; i < len; i += 4) {
            uint256 a = _b64CharToVal(data[i], table);
            uint256 b = _b64CharToVal(data[i + 1], table);
            uint256 c = _b64CharToVal(data[i + 2], table);
            uint256 d = _b64CharToVal(data[i + 3], table);

            uint256 triple = (a << 18) | (b << 12) | (c << 6) | d;

            if (j < decoded.length) decoded[j++] = bytes1(uint8(triple >> 16));
            if (j < decoded.length) decoded[j++] = bytes1(uint8(triple >> 8));
            if (j < decoded.length) decoded[j++] = bytes1(uint8(triple));
        }
        return decoded;
    }

    function _b64CharToVal(bytes1 char, bytes memory table) internal pure returns (uint256) {
        if (char == "=") return 0;
        for (uint256 i; i < 64; i++) {
            if (table[i] == char) return i;
        }
        revert("invalid base64 character");
    }
}
