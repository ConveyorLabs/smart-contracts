// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.15;

import "../lib/AggregatorV3Interface.sol";

contract GasOracle {
    address immutable gasOracleAddress;

    constructor(address _gasOracleAddress) {
        gasOracleAddress = _gasOracleAddress;
    }

    function getGasPrice() public view returns (uint256) {
        (, int256 answer, , , ) = IAggregatorV3(gasOracleAddress)
            .latestRoundData();
        return uint256(answer);
    }
}
