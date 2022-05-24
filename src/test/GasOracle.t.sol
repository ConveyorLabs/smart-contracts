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

contract GasOracleTest is DSTest {
    GasOracle gasOracle;

    function setUp() public {
        address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

        gasOracle = new GasOracle(aggregatorV3Address);
    }

    function testGetPrice() public view {
        gasOracle.getGasPrice();
    }
}
