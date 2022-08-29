// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../OrderBook.sol";

interface IOrderBook {
    ///@notice This function gets an order by the orderId. If the order does not exist, the order returned will be empty.
    function getOrderById(bytes32 orderId)
        external
        view
        returns (OrderBook.Order memory order);
}
