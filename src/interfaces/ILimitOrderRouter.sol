// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../SwapRouter.sol";

interface ILimitOrderExecutor {
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
        SwapRouter.SpotReserve[] memory spotReserveAToWeth,
        address[] memory lpAddressesAToWeth
    ) external view returns (SwapRouter.TokenToWethExecutionPrice[] memory);

    function _initializeTokenToTokenExecutionPrices(
        address tokenIn,
        SwapRouter.SpotReserve[] memory spotReserveAToWeth,
        address[] memory lpAddressesAToWeth,
        SwapRouter.SpotReserve[] memory spotReserveWethToB,
        address[] memory lpAddressWethToB
    ) external view returns (SwapRouter.TokenToTokenExecutionPrice[] memory);
}
