// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Restricted backing receipt; account entitlements reside in BucketPerps, not wallets.
contract BucketRewardToken is ERC20 {
    address public immutable controller;
    uint8 private immutable precision;

    error RestrictedReceipt();

    constructor(address controller_, uint8 decimals_) ERC20("BPERP", "BPERP") {
        controller = controller_;
        precision = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return precision;
    }

    function mint(uint256 units) external {
        if (msg.sender != controller) revert RestrictedReceipt();
        _mint(controller, units);
    }

    function burn(uint256 units) external {
        if (msg.sender != controller) revert RestrictedReceipt();
        _burn(controller, units);
    }

    function _update(address from, address to, uint256 units) internal override {
        if (from != address(0) && to != address(0)) revert RestrictedReceipt();
        super._update(from, to, units);
    }
}
