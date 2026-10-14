// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title PredictFWA
/// @notice A fixed supply of one billion PFWA, with 18 decimals and standard ERC-20 transfers.
/// @dev The immediate deployer receives the entire supply. There are no administrative powers.
contract PredictFWA is ERC20 {
    /// @notice Total supply in the token's smallest units (1 PFWA = 10**18 units).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("PredictFWA", "PFWA") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
