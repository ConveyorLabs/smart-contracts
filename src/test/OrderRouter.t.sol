// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";

import "../ConveyorLimitOrders.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "../../lib/libraries/PriceLibrary.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;
}

contract OrderRouterTest is DSTest {}

///@notice wrapper contract to expose internal functions for testing
contract OrderRouterWrapper is OrderRouter {
    function swap(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint256 _amountIn,
        uint256 _amountOutMin
    ) public {
        _swapV2(_tokenIn, _tokenOut, _lp, _amountIn, _amountOutMin);
    }
}
