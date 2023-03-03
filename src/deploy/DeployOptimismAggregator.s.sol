// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorSwapAggregator} from "../ConveyorSwapAggregator.sol";

contract Deploy is Script {
    ///@dev Fantom Constructor Constants
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant CONVEYOR_SWAP_EXECUTOR =
        0x0CF7f3F5f1Ff6580147f959519C4eb888b6F214E;

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
