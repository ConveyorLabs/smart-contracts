// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorSwapAggregator} from "../ConveyorSwapAggregator.sol";

contract Deploy is Script {
    ///@dev Avalanche Constructor Constants
    address constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
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
            WAVAX,
            CONVEYOR_SWAP_EXECUTOR
        );

        vm.stopBroadcast();
    }
}
