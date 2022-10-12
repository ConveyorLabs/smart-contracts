// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import "../SwapRouter.sol";
interface ILimitOrderQuoter {
    function _findBestTokenToTokenExecutionPrice(
        SwapRouter.TokenToTokenExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) external pure returns (uint256 bestPriceIndex);

    function simulateTokenToTokenPriceChange(
        uint128 alphaX,
        SwapRouter.TokenToTokenExecutionPrice memory executionPrice
    ) external returns (SwapRouter.TokenToTokenExecutionPrice memory);

    function simulateTokenToWethPriceChange(
        uint128 alphaX,
        SwapRouter.TokenToWethExecutionPrice memory executionPrice
    ) external returns (SwapRouter.TokenToWethExecutionPrice memory);

    function _findBestTokenToWethExecutionPrice(
        SwapRouter.TokenToWethExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) external pure returns (uint256 bestPriceIndex);

    function calculateAmountOutMinAToWeth(
        address lpAddressAToWeth,
        uint256 amountInOrder,
        uint16 taxIn,
        uint24 feeIn,
        address tokenIn
    ) external returns (uint256 amountOutMinAToWeth);

    function _initializeTokenToWethExecutionPrices(
        OrderBook.Order[] memory orders
    )
        external
        view
        returns (SwapRouter.TokenToWethExecutionPrice[] memory, uint128);
    function initializeTokenToTokenExecutionPrices(
        OrderBook.Order[] memory orders
    )
        external
        view
        returns (SwapRouter.TokenToTokenExecutionPrice[] memory, uint128);
}   
