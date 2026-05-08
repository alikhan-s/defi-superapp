// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title GovernanceToken
/// @notice ERC-20 token with on-chain voting power (ERC-5805) and gasless approvals (ERC-2612).
/// @dev Voting checkpoints are block-number based (default ERC20Votes clock).
///      Total supply is fixed at construction; no further minting is possible.
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes {
    // -------------------------------------------------------------------------
    // Custom errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when `initialSupply` is zero.
    error ZeroInitialSupply();

    /// @notice Thrown when `recipient` is the zero address.
    error ZeroRecipient();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @notice Deploy the governance token and mint the entire supply to `recipient`.
    /// @param name_          ERC-20 token name (e.g. "Governance Token").
    /// @param symbol_        ERC-20 ticker symbol (e.g. "GOV").
    /// @param initialSupply  Total token supply minted at construction (in raw units, 18 decimals).
    /// @param recipient      Address that receives the full initial supply.
    constructor(string memory name_, string memory symbol_, uint256 initialSupply, address recipient)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {
        if (initialSupply == 0) revert ZeroInitialSupply();
        if (recipient == address(0)) revert ZeroRecipient();
        _mint(recipient, initialSupply);
    }

    // -------------------------------------------------------------------------
    // ERC-20 metadata
    // -------------------------------------------------------------------------

    /// @notice Returns the number of decimals used for display.
    /// @return Always 18, per the standard ERC-20 convention.
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    // -------------------------------------------------------------------------
    // Required overrides
    // -------------------------------------------------------------------------

    /// @dev Overrides both ERC20 and ERC20Votes to ensure voting checkpoints are
    ///      updated on every transfer, mint, and burn.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /// @notice Returns the current nonce for `owner`, used by ERC-2612 permit.
    /// @param owner The address whose nonce is queried.
    /// @return Current nonce value.
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
