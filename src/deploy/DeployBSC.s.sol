// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.16;

// import {Script} from "../../lib/forge-std/src/Script.sol";
// import {ConveyorExecutor} from "../ConveyorExecutor.sol";
// import {SandboxLimitOrderBook} from "../SandboxLimitOrderBook.sol";
// import {SandboxLimitOrderRouter} from "../SandboxLimitOrderRouter.sol";
// import {ConveyorSwapAggregator} from "../ConveyorSwapAggregator.sol";
// import {LimitOrderRouter} from "../LimitOrderRouter.sol";
// import {LimitOrderQuoter} from "../LimitOrderQuoter.sol";
// import "../../test/utils/Console.sol";

// contract Deploy is Script {
//     /// @dev The salt used for the deployment of the Contracts

//     ///@dev Minimum Execution Credits
//     uint256 constant MINIMUM_EXECUTION_CREDITS = 1500000000000000;

//     address constant WETH = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
//     address constant USDC = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;

//     address constant PANCAKESWAP_V2 = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
//     address constant BISWAP = 0x858E3312ed3A876947EA49d572A7C42DE08af7EE;
//     address constant BABYDOGESWAP_V2 = 0x4693B62E5fc9c0a45F89D62e6300a03C85f43137;

//     function run()
//         public
//         returns (
//             ConveyorExecutor conveyorExecutor,
//             LimitOrderRouter limitOrderRouter,
//             SandboxLimitOrderBook sandboxLimitOrderBook,
//             SandboxLimitOrderRouter sandboxLimitOrderRouter,
//             LimitOrderQuoter limitOrderQuoter,
//             ConveyorSwapAggregator conveyorSwapAggregator
//         )
//     {
//         address[] memory _dexFactories = new address[](3);
//         bool[] memory _isUniV2 = new bool[](3);

//         _isUniV2[0] = true;
//         _isUniV2[1] = true;
//         _isUniV2[2] = true;

//         _dexFactories[0] = PANCAKESWAP_V2;
//         _dexFactories[1] = BISWAP;
//         _dexFactories[2] = BABYDOGESWAP_V2;

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

//         /// Deploy ConveyorSwapAggregator
//         conveyorSwapAggregator = new ConveyorSwapAggregator(
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