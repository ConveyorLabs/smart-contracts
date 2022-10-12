// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./interfaces/IOrderRouter.sol";


library LimitOrderQuoter  {
    
    ///@notice Function to return the index of the best price in the executionPrices array.
    ///@param executionPrices - Array of execution prices to evaluate.
    ///@param buyOrder - Boolean indicating whether the order is a buy or sell.
    ///@return bestPriceIndex - Index of the best price in the executionPrices array.
    function _findBestTokenToWethExecutionPrice(
        SwapRouter.TokenToWethExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) external pure returns (uint256 bestPriceIndex) {
        ///@notice If the order is a buy order, set the initial best price at 0.
        if (buyOrder) {
            uint256 bestPrice = 0;

            ///@notice For each exectution price in the executionPrices array.
            for (uint256 i = 0; i < executionPrices.length; ) {
                uint256 executionPrice = executionPrices[i].price;

                ///@notice If the execution price is better than the best exectuion price, update the bestPriceIndex.
                if (executionPrice < bestPrice && executionPrice != 0) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }

                unchecked {
                    ++i;
                }
            }
        } else {
            ///@notice If the order is a sell order, set the initial best price at max uint256.
            uint256 bestPrice = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            for (uint256 i = 0; i < executionPrices.length; ) {
                uint256 executionPrice = executionPrices[i].price;

                ///@notice If the execution price is better than the best exectuion price, update the bestPriceIndex.
                if (executionPrice > bestPrice && executionPrice != 0) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }

                unchecked {
                    ++i;
                }
            }
        }
    }

    ///@notice Function to return the index of the best price in the executionPrices array.
    ///@param executionPrices - Array of execution prices to evaluate.
    ///@param buyOrder - Boolean indicating whether the order is a buy or sell.
    ///@return bestPriceIndex - Index of the best price in the executionPrices array.
    function _findBestTokenToTokenExecutionPrice(
        SwapRouter.TokenToTokenExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) external pure returns (uint256 bestPriceIndex) {
        ///@notice If the order is a buy order, set the initial best price at 0.
        if (buyOrder) {
            uint256 bestPrice = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            ///@notice For each exectution price in the executionPrices array.
            for (uint256 i = 0; i < executionPrices.length; ) {
                uint256 executionPrice = executionPrices[i].price;
                ///@notice If the execution price is better than the best exectuion price, update the bestPriceIndex.
                if (executionPrice < bestPrice && executionPrice != 0) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }
                unchecked {
                    ++i;
                }
            }
        } else {
            uint256 bestPrice = 0;
            ///@notice If the order is a sell order, set the initial best price at max uint256.
            for (uint256 i = 0; i < executionPrices.length; i++) {
                uint256 executionPrice = executionPrices[i].price;
                ///@notice If the execution price is better than the best exectuion price, update the bestPriceIndex.
                if (executionPrice > bestPrice && executionPrice != 0) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }
            }
        }
    }

    ///@notice Function to retrieve the buy/sell status of a single order.
    ///@param order Order to determine buy/sell status on.
    ///@return bool Boolean indicating the buy/sell status of the order.
    function _buyOrSell(OrderBook.Order memory order)
        internal
        pure
        returns (bool)
    {
        if (order.buy) {
            return true;
        } else {
            return false;
        }
    }

    /// @notice Function to determine if an order meets the execution price.
    ///@param orderPrice The Spot price for execution of the order.
    ///@param executionPrice The current execution price of the best prices lp.
    ///@param buyOrder The buy/sell status of the order.
    function _orderMeetsExecutionPrice(
        uint256 orderPrice,
        uint256 executionPrice,
        bool buyOrder
    ) internal pure returns (bool) {
        if (buyOrder) {
            return executionPrice <= orderPrice;
        } else {
            return executionPrice >= orderPrice;
        }
    }

    ///@notice Checks if order can complete without hitting slippage
    ///@param spot_price The spot price of the liquidity pool.
    ///@param order_quantity The input quantity of the order.
    ///@param amountOutMin The slippage set by the order owner.
    function _orderCanExecute(
        uint256 spot_price,
        uint256 order_quantity,
        uint256 amountOutMin
    ) internal pure returns (bool) {
        return ConveyorMath.mul128I(spot_price, order_quantity) >= amountOutMin;
    }

}