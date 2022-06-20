// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.15;

import "./utils/test.sol";
import "../GasOracle.sol";

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
