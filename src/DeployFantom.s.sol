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

    address constant WETH = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address constant USDC = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;

    address constant SPIRIT_SWAP = 0xEF45d134b73241eDa7703fa787148D9C9F4950b0;
    address constant SPOOKY_SWAP = 0x152eE697f2E276fA89E96742e9bB9aB1F2E61bE3;
    address constant SUSHI_SWAP = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;

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
        _isUniV2[2] = true;

        _dexFactories[0] = SPIRIT_SWAP;
        _dexFactories[1] = SPOOKY_SWAP;
        _dexFactories[2] = SUSHI_SWAP;


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