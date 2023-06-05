// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorSwapAggregator} from "../ConveyorSwapAggregator.sol";

contract Deploy is Script {
    ///@dev BSC Constructor Constants
    address constant WETH = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    function run() public returns (ConveyorSwapAggregator conveyorSwapAggregator) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        /// Deploy ConveyorSwapAggregator
        conveyorSwapAggregator = new ConveyorSwapAggregator(
            WETH
        );

        vm.stopBroadcast();
    }
}
