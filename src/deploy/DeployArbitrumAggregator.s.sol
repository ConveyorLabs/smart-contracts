// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorRouterV1} from "../ConveyorRouterV1.sol";

contract Deploy is Script {
    ///@dev Arbitrum Constructor Constants
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function run() public returns (ConveyorRouterV1 conveyorRouterV1) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        /// Deploy ConveyorRouterV1
        conveyorRouterV1 = new ConveyorRouterV1(
            WETH
        );

        vm.stopBroadcast();
    }
}
