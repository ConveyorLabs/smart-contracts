// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import {Script} from "../../lib/forge-std/src/Script.sol";
// import {ConveyorExecutor} from "../ConveyorExecutor.sol";
// import {SandboxLimitOrderBook} from "../SandboxLimitOrderBook.sol";
// import {SandboxLimitOrderRouter} from "../SandboxLimitOrderRouter.sol";
// import {ConveyorRouterV1} from "../ConveyorRouterV1.sol";
// import {LimitOrderRouter} from "../LimitOrderRouter.sol";
// import {LimitOrderQuoter} from "../LimitOrderQuoter.sol";
// import "../../test/utils/Console.sol";

// contract Deploy is Script {
//     ///@dev Minimum Execution Credits
//     uint256 constant MINIMUM_EXECUTION_CREDITS = 1500000000000000;

//     address constant WETH = 0x4200000000000000000000000000000000000006;
//     address constant USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;

//     address constant UNISWAP_V3 = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

//     function run()
//         public
//         returns (
//             ConveyorExecutor conveyorExecutor,
//             LimitOrderRouter limitOrderRouter,
//             SandboxLimitOrderBook sandboxLimitOrderBook,
//             SandboxLimitOrderRouter sandboxLimitOrderRouter,
//             LimitOrderQuoter limitOrderQuoter,
//             ConveyorRouterV1 conveyorRouterV1
//         )
//     {
//         address[] memory _dexFactories = new address[](1);
//         bool[] memory _isUniV2 = new bool[](1);

//         _isUniV2[0] = false;
//         _dexFactories[0] = UNISWAP_V3;

//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

//         vm.startBroadcast(deployerPrivateKey);

//         /// Deploy LimitOrderQuoter
//         limitOrderQuoter = new LimitOrderQuoter(WETH);
//         /// Deploy ConveyorExecutor
//         conveyorExecutor = new ConveyorExecutor(
//             WETH,
//             USDC,
//             address(limitOrderQuoter),
//             _dexFactories,
//             _isUniV2,
//             MINIMUM_EXECUTION_CREDITS
//         );

//         /// Deploy ConveyorRouterV1
//         conveyorRouterV1 = new ConveyorRouterV1(
//             address(conveyorExecutor)
//         );

//         /// Deploy LimitOrderRouter
//         limitOrderRouter = new LimitOrderRouter(
//             WETH,
//             USDC,
//             address(conveyorExecutor),
//             MINIMUM_EXECUTION_CREDITS
//         );

//         /// Deploy SandboxLimitOrderBook
//         sandboxLimitOrderBook = new SandboxLimitOrderBook(
//             address(conveyorExecutor),
//             WETH,
//             USDC,
//             MINIMUM_EXECUTION_CREDITS
//         );

//         /// Deploy SandboxLimitOrderRouter
//         sandboxLimitOrderRouter = new SandboxLimitOrderRouter(
//             address(sandboxLimitOrderBook),
//             address(conveyorExecutor)
//         );

//         vm.stopBroadcast();
//     }
// }
