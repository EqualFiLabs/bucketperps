// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { MockPosition } from "../unit/Accounts.t.sol";
import { IStaticsAccountBridge } from "../../src/interfaces/IStaticsAccountBridge.sol";

/// @dev Proposed bridge fixture. It cannot establish compatibility with deployed Statics.
contract StaticsAccountMock is MockPosition, IStaticsAccountBridge {
    mapping(address => bool) public enabled;
    mapping(uint256 => mapping(bytes32 => bool)) public legs;
    mapping(uint256 => uint256) public activeLegCount;
    mapping(uint256 => bool) public initializing;
    mapping(uint256 => bool) public linked;
    mapping(uint256 => bool) public obligations;
    mapping(uint256 => bool) public morpho;
    mapping(uint256 => uint256) public multipliers;
    bool public reject;
    address public callback;
    bytes public callbackData;

    function configure(address module, bool allow) external {
        enabled[module] = allow;
    }

    function setGuards(uint256 id, bool init, bool link, bool debt, bool externalDebt) external {
        initializing[id] = init;
        linked[id] = link;
        obligations[id] = debt;
        morpho[id] = externalDebt;
    }

    function setFailure(bool fail, address target, bytes calldata data) external {
        reject = fail;
        callback = target;
        callbackData = data;
    }

    function attachExternalAccountLeg(uint256 id, bytes32 kind, bytes32 localId) external {
        ownerOf(id);
        require(!initializing[id] && enabled[msg.sender] && !reject, "attach rejected");
        bytes32 key = keccak256(abi.encode(msg.sender, kind, localId));
        if (!legs[id][key]) {
            legs[id][key] = true;
            ++activeLegCount[id];
        }
        _callback();
    }

    function detachExternalAccountLeg(uint256 id, bytes32 kind, bytes32 localId) external {
        require(!reject, "detach rejected");
        bytes32 key = keccak256(abi.encode(msg.sender, kind, localId));
        if (legs[id][key]) {
            delete legs[id][key];
            --activeLegCount[id];
        }
        _callback();
    }

    function accountMultiplierBps(uint256 id) external view returns (uint256) {
        return multipliers[id] == 0 ? 10_000 : multipliers[id];
    }

    function changeMultiplier(address module, uint256 id, uint256 nextBps) external {
        uint256 previous = multipliers[id] == 0 ? 10_000 : multipliers[id];
        multipliers[id] = nextBps;
        (bool ok, bytes memory result) = module.call(
            abi.encodeWithSignature(
                "onAccountMultiplierChanged(uint256,uint256,uint256)", id, previous, nextBps
            )
        );
        if (!ok) {
            assembly { revert(add(result, 32), mload(result)) }
        }
    }

    function close(uint256 id) external {
        require(msg.sender == ownerOf(id));
        require(!initializing[id] && activeLegCount[id] == 0 && !obligations[id] && !morpho[id]);
        delete owners[id];
        delete getApproved[id];
    }

    function transferFrom(address from, address to, uint256 id) public override {
        require(!linked[id] && !initializing[id], "transfer locked");
        super.transferFrom(from, to, id);
    }

    function _callback() private {
        if (callback != address(0)) {
            (bool ok, bytes memory result) = callback.call(callbackData);
            if (!ok) {
                assembly { revert(add(result, 32), mload(result)) }
            }
        }
    }
}
