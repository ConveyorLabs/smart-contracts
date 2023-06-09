// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.16;

// import {Script} from "../../lib/forge-std/src/Script.sol";
// import {UniswapInterfaceMulticall} from "../UniswapInterfaceMulticall.sol";
// contract Deploy is Script {

//     function run()
//         public
//         returns (UniswapInterfaceMulticall uniswapInterfaceMulticall)
//     {
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

//         vm.startBroadcast(deployerPrivateKey);

//         /// Deploy ConveyorRouterV1
//         uniswapInterfaceMulticall = new UniswapInterfaceMulticall();

//         vm.stopBroadcast();
//     }
// }