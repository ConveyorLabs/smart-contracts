// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorSwapAggregator} from "../ConveyorSwapAggregator.sol";

contract Deploy is Script {
    ///@dev Arbitrum Constructor Constants
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant CONVEYOR_SWAP_EXECUTOR =
        0x3c37AFb914721bcb1D8eEFF45fB91A99A3ef65DF;

    function run()
        public
        returns (ConveyorSwapAggregator conveyorSwapAggregator)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        /// Deploy ConveyorSwapAggregator
        conveyorSwapAggregator = new ConveyorSwapAggregator(
            WETH,
            CONVEYOR_SWAP_EXECUTOR
        );

        vm.stopBroadcast();
    }
}
