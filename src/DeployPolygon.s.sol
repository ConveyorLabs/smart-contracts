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
    ///@dev Minimum Execution Credits
    uint256 constant MINIMUM_EXECUTION_CREDITS = 1500000000000000;

    ///@dev Polygon Constructor Constants
    address constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    ///@dev Cfmm Factory addresses & deployment hashes
    address constant SUSHISWAP = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;
    address constant QUICKSWAP = 0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32;
    address constant UNISWAP_V3 = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    function run()
        public
        returns (
            ConveyorExecutor conveyorExecutor,
            LimitOrderRouter limitOrderRouter,
            SandboxLimitOrderBook sandboxLimitOrderBook,
            SandboxLimitOrderRouter sandboxLimitOrderRouter,
            LimitOrderQuoter limitOrderQuoter,
            ConveyorSwapAggregator conveyorSwapAggregator
        )
    {
        address[] memory _dexFactories = new address[](3);
        bool[] memory _isUniV2 = new bool[](3);

        _isUniV2[0] = true;
        _isUniV2[1] = true;
        _isUniV2[2] = false;

        _dexFactories[0] = SUSHISWAP;
        _dexFactories[1] = QUICKSWAP;
        _dexFactories[2] = UNISWAP_V3;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        /// Deploy LimitOrderQuoter
        limitOrderQuoter = new LimitOrderQuoter(WMATIC);
        /// Deploy ConveyorExecutor
        conveyorExecutor = new ConveyorExecutor(
            WMATIC,
            USDC,
            address(limitOrderQuoter),
            _dexFactories,
            _isUniV2,
            MINIMUM_EXECUTION_CREDITS
        );

        /// Deploy ConveyorSwapAggregator
        conveyorSwapAggregator = new ConveyorSwapAggregator(
            address(conveyorExecutor)
        );

        /// Deploy LimitOrderRouter
        limitOrderRouter = new LimitOrderRouter(
            WMATIC,
            USDC,
            address(conveyorExecutor),
            MINIMUM_EXECUTION_CREDITS
        );

        /// Deploy SandboxLimitOrderBook
        sandboxLimitOrderBook = new SandboxLimitOrderBook(
            address(conveyorExecutor),
            WMATIC,
            USDC,
            MINIMUM_EXECUTION_CREDITS
        );

        /// Deploy SandboxLimitOrderRouter
        sandboxLimitOrderRouter = new SandboxLimitOrderRouter(
            address(sandboxLimitOrderBook),
            address(conveyorExecutor)
        );

        vm.stopBroadcast();
    }
    
}
