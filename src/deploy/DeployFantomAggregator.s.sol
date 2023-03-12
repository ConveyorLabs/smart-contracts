// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.16;

// import {Script} from "../../lib/forge-std/src/Script.sol";
// import {ConveyorSwapAggregator} from "../ConveyorSwapAggregator.sol";

// contract Deploy is Script {
//     ///@dev Fantom Constructor Constants
//     address constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
//     address constant CONVEYOR_SWAP_EXECUTOR =
//         0xaF0a804C877d3C3984A5f92E676737CaBedF5066;

//     function run()
//         public
//         returns (ConveyorSwapAggregator conveyorSwapAggregator)
//     {
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

//         vm.startBroadcast(deployerPrivateKey);

//         /// Deploy ConveyorSwapAggregator
//         conveyorSwapAggregator = new ConveyorSwapAggregator(
//             WFTM,
//             CONVEYOR_SWAP_EXECUTOR
//         );

//         vm.stopBroadcast();
//     }
// }
