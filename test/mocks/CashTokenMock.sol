// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CashTokenMock is ERC20 {
    uint8 internal immutable precision;
    uint256 public transferFee;
    bool public reject;
    address public callback;
    bytes public callbackData;

    constructor(uint8 decimals_) ERC20("Fixture Cash", "FC") {
        precision = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return precision;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function configure(uint256 fee, bool fail, address target, bytes calldata data) external {
        transferFee = fee;
        reject = fail;
        callback = target;
        callbackData = data;
    }

    function _update(address from, address to, uint256 amount) internal override {
        require(!reject, "token rejected");
        uint256 fee = from != address(0) && to != address(0) ? transferFee : 0;
        super._update(from, to, amount - fee);
        if (fee != 0) super._update(from, address(0), fee);
        if (callback != address(0)) {
            (bool ok, bytes memory result) = callback.call(callbackData);
            if (!ok) {
                assembly { revert(add(result, 32), mload(result)) }
            }
        }
    }
}
