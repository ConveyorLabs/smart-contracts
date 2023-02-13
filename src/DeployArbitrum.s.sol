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

    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    address constant CAMELOT = 0x6EcCab422D763aC031210895C81787E87B43A652;
    address constant SUSHISWAP_V2 = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
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

        _dexFactories[0] = CAMELOT;
        _dexFactories[1] = SUSHISWAP_V2;
        _dexFactories[2] = UNISWAP_V3;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        /// Deploy LimitOrderQuoter
        limitOrderQuoter = new LimitOrderQuoter(WETH);
        /// Deploy ConveyorExecutor
        conveyorExecutor = new ConveyorExecutor(
            WETH,
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
            WETH,
            USDC,
            address(conveyorExecutor),
            MINIMUM_EXECUTION_CREDITS
        );

        /// Deploy SandboxLimitOrderBook
        sandboxLimitOrderBook = new SandboxLimitOrderBook(
            address(conveyorExecutor),
            WETH,
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