// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorRouterV1} from "../ConveyorRouterV1.sol";

contract Deploy is Script {
    ///@dev BSC Constructor Constants
    address constant WETH = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    function run() public returns (ConveyorRouterV1 conveyorRouterV1) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        /// Deploy ConveyorRouterV1
        conveyorRouterV1 = new ConveyorRouterV1(
            WETH,
            0
        );

        vm.stopBroadcast();
    }
}
