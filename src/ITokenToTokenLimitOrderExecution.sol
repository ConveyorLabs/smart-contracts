// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/ConveyorMath.sol";
import "../lib/libraries/Uniswap/SqrtPriceMath.sol";
import "./OrderBook.sol";
import "./OrderRouter.sol";
import "./ConveyorErrors.sol";
import "../lib/libraries/Uniswap/FullMath.sol";
import "../lib/interfaces/token/IWETH.sol";
import "../lib/interfaces/uniswap-v3/IQuoter.sol";
import "../lib/libraries/ConveyorTickMath.sol";

/// @title OrderRouter
/// @author LeytonTaylor, 0xKitsune, Conveyor Labs
/// @notice Limit Order contract to execute existing limit orders within the OrderBook contract.
interface ITokenToTokenExecution {
    ///@notice Function to execute an array of TokenToToken orders
    ///@param orders - Array of orders to be executed.
    function executeTokenToTokenOrders(OrderBook.Order[] memory orders) external;

    ///@notice Function to execute an array of TokenToToken orders
    ///@param orders - Array of orders to be executed.
    function executeTokenToTokenOrderSingle(OrderBook.Order[] memory orders) external;
    
}