// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorRouterV1} from "../ConveyorRouterV1.sol";

contract Deploy is Script {
    ///@dev Fantom Constructor Constants
    address constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;

    function run()
        public
        returns (ConveyorRouterV1 conveyorRouterV1)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        /// Deploy ConveyorRouterV1
        conveyorRouterV1 = new ConveyorRouterV1(
            WFTM
        );

        vm.stopBroadcast();
    }
}
