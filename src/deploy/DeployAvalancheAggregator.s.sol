// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorRouterV1} from "../ConveyorRouterV1.sol";

contract Deploy is Script {
    ///@dev Avalanche Constructor Constants
    address constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    function run() public returns (ConveyorRouterV1 conveyorRouterV1) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        /// Deploy ConveyorRouterV1
        conveyorRouterV1 = new ConveyorRouterV1(WAVAX);

        vm.stopBroadcast();
    }
}
