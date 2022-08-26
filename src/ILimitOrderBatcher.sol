// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./OrderBook.sol";
import "./OrderRouter.sol";

interface ILimitOrderBatcher {
    function batchTokenToTokenOrders(
        OrderBook.Order[] memory orders,
        OrderRouter.TokenToTokenExecutionPrice[] memory executionPrices
    ) external returns (OrderRouter.TokenToTokenBatchOrder[] memory);

    function findBestTokenToTokenExecutionPrice(
        OrderRouter.TokenToTokenExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) external pure returns (uint256 bestPriceIndex);

    function calculateAmountOutMinAToWeth(
        address lpAddressAToWeth,
        uint256 amountInOrder,
        uint16 taxIn,
        uint24 feeIn,
        address tokenIn
    ) external returns (uint256 amountOutMinAToWeth);

    function initializeTokenToTokenExecutionPrices(
        OrderBook.Order[] memory orders
    )
        external
        view
        returns (OrderRouter.TokenToTokenExecutionPrice[] memory, uint128);
}
