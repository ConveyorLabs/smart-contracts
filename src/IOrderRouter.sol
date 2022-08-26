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
}