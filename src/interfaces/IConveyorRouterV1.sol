// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../ConveyorRouterV1.sol";

interface IConveyorRouterV1 {
    function swapExactTokenForToken(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        ConveyorRouterV1.SwapAggregatorGenericMulticall
            calldata genericMulticall
    ) external payable;

    function swapExactTokenForEth(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        ConveyorRouterV1.SwapAggregatorGenericMulticall
            calldata swapAggregatorMulticall
    ) external payable;

    function swapExactEthForToken(
        address tokenOut,
        uint128 amountOutMin,
        uint128 protocolFee,
        ConveyorRouterV1.SwapAggregatorGenericMulticall
            calldata swapAggregatorMulticall
    ) external payable;

    function quoteSwapExactTokenForToken(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        ConveyorRouterV1.SwapAggregatorGenericMulticall
            calldata swapAggregatorMulticall
    ) external payable returns (uint256 gasConsumed);

    function quoteSwapExactTokenForEth(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        ConveyorRouterV1.SwapAggregatorGenericMulticall
            calldata swapAggregatorMulticall
    ) external payable returns (uint256 gasConsumed);

    function quoteSwapExactEthForToken(
        address tokenOut,
        uint128 amountOutMin,
        uint128 protocolFee,
        ConveyorRouterV1.SwapAggregatorGenericMulticall
            calldata swapAggregatorMulticall
    ) external payable returns (uint256 gasConsumed);

    function withdraw() external;

    function CONVEYOR_MULTICALL() external view returns (address);
}
