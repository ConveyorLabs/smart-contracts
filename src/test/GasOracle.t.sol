// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./utils/test.sol";
import "../GasOracle.sol";

contract GasOracleTest is DSTest {
    GasOracle gasOracle;

    function setUp() public {
        ///@notice This is the fast gas oracle address for Ethereum Mainnet
        address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;
        gasOracle = new GasOracle(aggregatorV3Address);
    }

    ///TODO: validate results
    function testGetPrice() public view {
        gasOracle.getGasPrice();
    }
}
