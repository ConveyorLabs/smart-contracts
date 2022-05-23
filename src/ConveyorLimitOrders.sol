// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "../lib/interfaces/token/IERC20.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "./test/utils/Console.sol";
import "../lib/libraries/uniswap/OracleLibrary.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/PriceLibrary.sol";
import "../lib/libraries/ConveyorMath64x64.sol";

import "./OrderBook.sol";
import "./OrderRouter.sol";

///@notice for all order placement, order updates and order cancelation logic, see OrderBook
///@notice for all order fulfuillment logic, see OrderRouter

contract ConveyorLimitOrders is OrderBook, OrderRouter {
    //----------------------Modifiers------------------------------------//

    modifier onlyEOA() {
        require(msg.sender == tx.origin);
        _;
    }

    //----------------------Constructor------------------------------------//

    constructor(address _gasOracle, address other) OrderBook(_gasOracle) {}

    //----------------------Functions------------------------------------//

    /// @notice execute all orders passed from beacon matching order execution criteria. i.e. 'orderPrice' matches observable lp price for all orders
    /// @param orders := array of orders to be executed within the mapping
    function executeOrders(Order[] memory orders) external onlyEOA {
        //iterate through orders and try to fill order
        for (uint256 i = 0; i < orders.length; ++i) {
            Order memory order = orders[i];
            //check the execution price of the order

            //check the price of the lp

            //note: can either loop through and execute or aggregate and execute

            //loop through orders and see which ones hit the execution price

            //if execution price hit
            //add the order to executableOrders, update total

            //aggregate the value of all of the orders
        }
    }
}
