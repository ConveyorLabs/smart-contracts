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
    /// @dev The salt used for the deployment of the Contracts
    bytes32 internal constant SALT = bytes32("0x2efa_abdd");

    ///@dev Minimum Execution Credits
    uint256 constant MINIMUM_EXECUTION_CREDITS = 1500000000000000;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNISWAP_V2 = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address constant PANCAKESWAP_V2 =
        0x1097053Fd2ea711dad45caCcc45EfF7548fCB362;
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
        address[] memory _dexFactories = new address[](4);
        bool[] memory _isUniV2 = new bool[](4);

        _isUniV2[0] = true;
        _isUniV2[1] = true;
        _isUniV2[2] = true;
        _isUniV2[3] = false;

        _dexFactories[0] = UNISWAP_V2;
        _dexFactories[1] = SUSHISWAP_V2;
        _dexFactories[2] = PANCAKESWAP_V2;
        _dexFactories[3] = UNISWAP_V3;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        /// Deploy LimitOrderQuoter
        limitOrderQuoter = new LimitOrderQuoter{salt: SALT}(WETH);
        /// Deploy ConveyorExecutor
        conveyorExecutor = new ConveyorExecutor{salt: SALT}(
            WETH,
            USDC,
            address(limitOrderQuoter),
            _dexFactories,
            _isUniV2,
            MINIMUM_EXECUTION_CREDITS
        );

        /// Deploy ConveyorSwapAggregator
        conveyorSwapAggregator = new ConveyorSwapAggregator{salt: SALT}(
            address(conveyorExecutor)
        );

        /// Deploy LimitOrderRouter
        limitOrderRouter = new LimitOrderRouter{salt: SALT}(
            WETH,
            USDC,
            address(conveyorExecutor),
            MINIMUM_EXECUTION_CREDITS
        );

        /// Deploy SandboxLimitOrderBook
        sandboxLimitOrderBook = new SandboxLimitOrderBook{salt: SALT}(
            address(conveyorExecutor),
            WETH,
            USDC,
            MINIMUM_EXECUTION_CREDITS
        );

        /// Deploy SandboxLimitOrderRouter
        sandboxLimitOrderRouter = new SandboxLimitOrderRouter{salt: SALT}(
            address(sandboxLimitOrderBook),
            address(conveyorExecutor)
        );

        vm.stopBroadcast();
    }
}
