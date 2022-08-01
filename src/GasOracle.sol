// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../lib/AggregatorV3Interface.sol";

/// @title GasOracle
/// @author LeytonTaylor, 0xKitsune
/// @notice This contract fetches the latest fast gas price from the Chainlink Gas Oracle
contract GasOracle {
    ///@notice The gasOracleAddress is the address of the Chainlink Gas Oracle
    address immutable gasOracleAddress;

    constructor(address _gasOracleAddress) {
        gasOracleAddress = _gasOracleAddress;
    }

    ///@notice Gets the latest gas price from the Chainlink data feed for the fast gas oracle
    //TODO: FIXME: stale gas result check
    function getGasPrice() public view returns (uint256) {
        (, int256 answer, , , ) = IAggregatorV3(gasOracleAddress)
            .latestRoundData();
        return uint256(answer);
    }
}
