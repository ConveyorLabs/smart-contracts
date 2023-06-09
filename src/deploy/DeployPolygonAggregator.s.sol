// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorRouterV1} from "../ConveyorRouterV1.sol";

contract Deploy is Script {
    ///@dev Polygon Constructor Constants
    address constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;


    function run()
        public
        returns (ConveyorRouterV1 conveyorRouterV1)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        /// Deploy ConveyorRouterV1
        conveyorRouterV1 = new ConveyorRouterV1(
            WMATIC
        );
        vm.stopBroadcast();
    }
}
