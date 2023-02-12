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
    bytes32 internal constant SALT = bytes32("0x2efa_abda");

    ///@dev Minimum Execution Credits
    uint256 constant MINIMUM_EXECUTION_CREDITS = 1500000000000000;

    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;

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
        address[] memory _dexFactories = new address[](1);
        bool[] memory _isUniV2 = new bool[](1);

        _isUniV2[0] = false;
        _dexFactories[0] = UNISWAP_V3;

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