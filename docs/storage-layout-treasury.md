# Treasury Storage Layout (V1 to V2)

This document provides a proof of compatibility for the storage layout during the UUPS upgrade from `TreasuryV1` to `TreasuryV2`.

## Storage Collision Prevention
To prevent storage collisions when upgrading, `TreasuryV1` implements a gap (`uint256[48] private __gap;`) at the end of its storage space. When `TreasuryV2` inherits from `TreasuryV1`, all newly added state variables are placed strictly after the variables and the gap of `TreasuryV1`. 

## Slot Allocation Map

### TreasuryV1 Slots
| Variable | Type | Inherited From | Slot Offset |
| :--- | :--- | :--- | :--- |
| `_initialized` | uint8 | Initializable | 0 |
| `_initializing` | bool | Initializable | 0 |
| `_roles` | mapping | AccessControlUpgradeable | 1 |
| `_paused` | bool | PausableUpgradeable | 2 |
| `totalETHWithdrawn` | uint256 | TreasuryV1 | 3 |
| `totalERC20Withdrawn` | mapping | TreasuryV1 | 4 |
| `__gap` | uint256[48] | TreasuryV1 | 5 - 52 |

### TreasuryV2 Slots
| Variable | Type | Inherited From | Slot Offset |
| :--- | :--- | :--- | :--- |
| **All V1 slots preserved** | **various** | **TreasuryV1** | **0 - 52** |
| `lastBatchTimestamp` | uint256 | TreasuryV2 | 53 |

By appending `lastBatchTimestamp` after the initial layout and the `__gap` array, V2 correctly preserves the first 53 slots, ensuring 100% storage layout compatibility.