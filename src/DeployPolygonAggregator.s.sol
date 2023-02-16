// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Script} from "../lib/forge-std/src/Script.sol";
import {ConveyorExecutor} from "../src/ConveyorExecutor.sol";
import {SandboxLimitOrderBook} from "../src/SandboxLimitOrderBook.sol";
import {SandboxLimitOrderRouter} from "../src/SandboxLimitOrderRouter.sol";
import {ConveyorSwapAggregator} from "../src/ConveyorSwapAggregator.sol";
import {LimitOrderRouter} from "../src/LimitOrderRouter.sol";
import {LimitOrderQuoter} from "../src/LimitOrderQuoter.sol";
import "../src/test/utils/Console.sol";

contract Deploy is Script {
    ///@dev Polygon Constructor Constants
    address constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    function run()
        public
        returns (ConveyorSwapAggregator conveyorSwapAggregator)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        /// Deploy ConveyorSwapAggregator
        conveyorSwapAggregator = new ConveyorSwapAggregator(WMATIC);
        vm.stopBroadcast();
    }
}
