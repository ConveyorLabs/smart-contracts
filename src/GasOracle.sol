// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../lib/AggregatorV3Interface.sol";

/// @title GasOracle
/// @author LeytonTaylor, 0xKitsune
/// @notice This contract fetches the latest fast gas price from the Chainlink Gas Oracle
contract GasOracle {
    ///@notice The gasOracleAddress is the address of the Chainlink Gas Oracle.
    address immutable gasOracleAddress;

    ///@notice Stale Price delay interval between blocks.
    constructor(address _gasOracleAddress) {
        require(_gasOracleAddress != address(0), "Invalid address");
        gasOracleAddress = _gasOracleAddress;
    }

    ///@notice Gets the latest gas price from the Chainlink data feed for the fast gas oracle
    function getGasPrice() public view returns (uint256) {
        (, int256 answer, , , ) = IAggregatorV3(gasOracleAddress)
            .latestRoundData();

        return uint256(answer);
    }
}
