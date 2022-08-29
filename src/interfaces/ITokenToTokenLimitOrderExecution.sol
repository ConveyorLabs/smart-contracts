// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../OrderBook.sol";

/// @title SwapRouter
/// @author LeytonTaylor, 0xKitsune, Conveyor Labs
/// @notice Limit Order contract to execute existing limit orders within the OrderBook contract.
interface ITokenToTokenExecution {
    ///@notice Function to execute an array of TokenToToken orders
    ///@param orders - Array of orders to be executed.
    function executeTokenToTokenOrders(OrderBook.Order[] memory orders)
        external;

    ///@notice Function to execute an array of TokenToToken orders
    ///@param orders - Array of orders to be executed.
    function executeTokenToTokenOrderSingle(OrderBook.Order[] memory orders)
        external;
}
