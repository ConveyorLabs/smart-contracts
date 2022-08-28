// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./OrderRouter.sol";
import "./OrderBook.sol";

interface IOrderRouter {
    function getAllPrices(
        address token0,
        address token1,
        uint24 FEE
    )
        external
        view
        returns (OrderRouter.SpotReserve[] memory prices, address[] memory lps);

    function calculateMaxBeaconReward(
        OrderRouter.SpotReserve[] memory spotReserves,
        OrderBook.Order[] memory orders,
        bool wethIsToken0
    ) external view returns (uint128 maxBeaconReward);

    function calculateFee(
        uint128 amountIn,
        address usdc,
        address weth
    ) external view returns (uint128);

    function swap(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _reciever,
        address _sender
    ) external returns (uint256 amountRecieved);

    function calculateReward(uint128 percentFee, uint128 wethValue)
        external
        pure
        returns (uint128 conveyorReward, uint128 beaconReward);

    function transferTokensToContract(OrderBook.Order memory order)
        external
        returns (bool success);

    function transferTokensOutToOwner(address owner, uint256 amount, address tokenOut) external;

     function transferBeaconReward(uint256 totalBeaconReward, address executorAddress, address weth) external;
}
