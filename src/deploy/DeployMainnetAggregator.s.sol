// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorRouterV1} from "../ConveyorRouterV1.sol";

contract Deploy is Script {
    ///@dev Mainnet Constructor Constants
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function run()
        public
        returns (ConveyorRouterV1 conveyorRouterV1)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        /// Deploy ConveyorRouterV1
        conveyorRouterV1 = new ConveyorRouterV1(WETH);

        vm.stopBroadcast();
    }
}
