// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../ConveyorRouterV1.sol";

interface IConveyorRouterV1 {
    function swapExactTokenForToken(
        address tokenIn,
        address tokenOut,
        ConveyorRouterV1.SwapData calldata swapData,
        ConveyorRouterV1.SwapAggregatorGenericMulticall calldata genericMulticall
    ) external payable;

    function swapExactEthForToken(
        address tokenOut,
        ConveyorRouterV1.EthToTokenSwapData calldata swapData,
        ConveyorRouterV1.SwapAggregatorGenericMulticall calldata swapAggregatorMulticall
    ) external payable;

    function swapExactTokenForEth(
        address tokenIn,
        ConveyorRouterV1.SwapData calldata swapData,
        ConveyorRouterV1.SwapAggregatorGenericMulticall calldata swapAggregatorMulticall
    ) external payable;

    function setAffiliate(uint16 affiliateId, address affiliateAddress) external;

    function upgradeMulticall(bytes memory bytecode, bytes32 salt) external payable returns (address);

    function quoteSwapExactTokenForToken(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        ConveyorRouterV1.SwapAggregatorGenericMulticall calldata swapAggregatorMulticall
    ) external payable returns (uint256 gasConsumed);

    function quoteSwapExactTokenForEth(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        ConveyorRouterV1.SwapAggregatorGenericMulticall calldata swapAggregatorMulticall
    ) external payable returns (uint256 gasConsumed);

    function quoteSwapExactEthForToken(
        address tokenOut,
        uint128 amountOutMin,
        uint128 protocolFee,
        ConveyorRouterV1.SwapAggregatorGenericMulticall calldata swapAggregatorMulticall
    ) external payable returns (uint256 gasConsumed);

    function withdraw() external;

    function CONVEYOR_MULTICALL() external view returns (address);
}
