// // SPDX-License-Identifier: MIT
// pragma solidity =0.8.21;

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

//     address constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
//     address constant USDC = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;

//     address constant SPIRITSWAP = 0xEF45d134b73241eDa7703fa787148D9C9F4950b0;
//     address constant SPOOKYSWAP = 0x152eE697f2E276fA89E96742e9bB9aB1F2E61bE3;
//     address constant SUSHISWAP = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;

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
//         address[] memory _dexFactories = new address[](3);
//         bool[] memory _isUniV2 = new bool[](3);

//         _isUniV2[0] = true;
//         _isUniV2[1] = true;
//         _isUniV2[2] = true;

//         _dexFactories[0] = SPIRITSWAP;
//         _dexFactories[1] = SPOOKYSWAP;
//         _dexFactories[2] = SUSHISWAP;

//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

//         vm.startBroadcast(deployerPrivateKey);

//         /// Deploy LimitOrderQuoter
//         limitOrderQuoter = new LimitOrderQuoter(WFTM);
//         /// Deploy ConveyorExecutor
//         conveyorExecutor = new ConveyorExecutor(
//             WFTM,
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
//             WFTM,
//             USDC,
//             address(conveyorExecutor),
//             MINIMUM_EXECUTION_CREDITS
//         );

//         /// Deploy SandboxLimitOrderBook
//         sandboxLimitOrderBook = new SandboxLimitOrderBook(
//             address(conveyorExecutor),
//             WFTM,
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
