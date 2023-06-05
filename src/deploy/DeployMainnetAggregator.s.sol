// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorSwapAggregator} from "../ConveyorSwapAggregator.sol";

contract Deploy is Script {
    ///@dev Mainnet Constructor Constants
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function run() public returns (ConveyorSwapAggregator conveyorSwapAggregator) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        /// Deploy ConveyorSwapAggregator
        conveyorSwapAggregator = new ConveyorSwapAggregator(WETH);

        vm.stopBroadcast();
    }
}
