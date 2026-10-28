// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;
import { DeploymentCuts } from "./DeploymentCuts.sol";
import { BucketPerpsDiamond } from "../src/BucketPerpsDiamond.sol";
import { BucketPerpsInit } from "../src/init/BucketPerpsInit.sol";
import { IDiamondCut } from "../src/interfaces/IDiamondCut.sol";

/// @notice Caller supplies the complete configuration; this script invents no chain identities or economics.
contract DeployBucketPerps is DeploymentCuts {
    event DeploymentPrepared(address indexed diamond, address indexed initializer, uint256 chainId);

    function run(
        address governor,
        address guardian,
        uint64 upgradeDelay,
        BucketPerpsInit.Config calldata configuration
    ) external returns (BucketPerpsDiamond diamond) {
        vm.startBroadcast();
        diamond = deploy(governor, guardian, upgradeDelay, configuration);
        vm.stopBroadcast();
    }

    function deploy(
        address governor,
        address guardian,
        uint64 upgradeDelay,
        BucketPerpsInit.Config memory configuration
    ) public returns (BucketPerpsDiamond diamond) {
        IDiamondCut.FacetCut[] memory cuts = deployCuts();
        address initializer = _deploy("BucketPerpsInit.sol:BucketPerpsInit", "");
        BucketPerpsDiamond.Bootstrap memory b = BucketPerpsDiamond.Bootstrap(
            governor,
            guardian,
            upgradeDelay,
            cuts,
            initializer,
            abi.encodeCall(BucketPerpsInit.initialize, (configuration))
        );
        diamond =
            BucketPerpsDiamond(payable(_deploy("BucketPerpsDiamond.sol:BucketPerpsDiamond", abi.encode(b))));
        emit DeploymentPrepared(address(diamond), initializer, block.chainid);
    }
}
