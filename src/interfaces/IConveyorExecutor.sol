// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../LimitOrderBook.sol";

interface IConveyorExecutor {
    function executeTokenToWethOrders(LimitOrderBook.LimitOrder[] memory orders)
        external
        returns (uint256, uint256);

    function executeTokenToTokenOrders(
        LimitOrderBook.LimitOrder[] memory orders
    ) external returns (uint256, uint256);
}
