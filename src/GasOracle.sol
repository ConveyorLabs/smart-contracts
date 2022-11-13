// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/AggregatorV3Interface.sol";
import "./lib/ConveyorMath.sol";
import "./test/utils/Console.sol";

/// @title GasOracle
/// @author 0xOsiris, 0xKitsune
/// @notice This contract fetches the latest fast gas price from the Chainlink Gas Oracle
contract GasOracle {
    uint256 constant ONE_HUNDRED_TWENTY_FIVE = 125;
    uint256 constant ONE_HUNDRED = 100;
    ///@notice Time horizon for arithmetic mean of has price.
    uint256 constant timeHorizon = 86400;

    ///@notice The gasOracleAddress is the address of the Chainlink Gas Oracle.
    address immutable gasOracleAddress;

    ///@notice Last timestamp that the getGasPrice() function was called.
    uint256 lastGasOracleTimestamp;
    ///@notice Mean of gas oracle prices across the time horizon
    uint256 meanGasPrice;

    event MeanGasPriceUpdate(
        uint256 timestamp,
        uint256 gasPrice,
        uint256 meanGasPrice
    );

    ///@notice Stale Price delay interval between blocks.
    constructor(address _gasOracleAddress) {
        require(_gasOracleAddress != address(0), "Invalid address");
        gasOracleAddress = _gasOracleAddress;

        (, int256 answer, , , ) = IAggregatorV3(gasOracleAddress)
            .latestRoundData();
        meanGasPrice = uint256(answer);
        lastGasOracleTimestamp = block.timestamp;
    }

    ///@notice Gets the latest gas price from the Chainlink data feed for the fast gas oracle
    function getGasPrice() public returns (uint256) {
        bool sufficientlyElapsedTime;
        assembly {
            sufficientlyElapsedTime := iszero(
                ///@notice Limit only 1 call to to the oracle per block.
                lt(
                    sub(timeHorizon, 1),
                    sub(
                        timeHorizon,
                        sub(lastGasOracleTimestamp.slot, timestamp())
                    )
                )
            )
        }
        if (sufficientlyElapsedTime) {
            (, int256 answer, , , ) = IAggregatorV3(gasOracleAddress)
                .latestRoundData();

            uint256 gasPrice = uint256(answer);

            uint128 proportionalTimeHorizonElapsed = ConveyorMath.divUU(
                block.timestamp - lastGasOracleTimestamp,
                timeHorizon
            );
            console.log(proportionalTimeHorizonElapsed);

            uint128 divisor = (uint128(1) +
                (ConveyorMath.divUU(
                    block.timestamp - lastGasOracleTimestamp,
                    timeHorizon
                ) % 2**64));

            ///@notice update the meanGasPrice
            meanGasPrice = ConveyorMath.divUU(
                uint256(
                    meanGasPrice +
                        ConveyorMath.mul64U(
                            proportionalTimeHorizonElapsed,
                            gasPrice
                        )
                ),
                uint256(divisor)
            );

            emit MeanGasPriceUpdate(block.timestamp, gasPrice, meanGasPrice);

            ///@notice Update the last gas timestamp
            lastGasOracleTimestamp = block.timestamp;

            ///@notice
            /* The gas price is determined to be the oracleGasPrice * 1.25 since the Chainlink Gas Oracle can deviate up to 25% between updates
         If the Chainlink Gas oracle is reporting a price that is 25% less than the actual price, then the adjustedGasPrice will report the fair market gas price
         If the Gas oracle is reporting a price 25% greater than the actual gas price, the adjusted price is still 25% greater than the oracle.
         This allows for the off chain executor to always be incentivized to execute a transaction, regardless of how far the gasOracle deviates
         from the fair market price. 
        */

            uint256 adjustedGasPrice = (uint256(meanGasPrice) *
                ONE_HUNDRED_TWENTY_FIVE) / ONE_HUNDRED;
            return adjustedGasPrice;
        } else {
            return meanGasPrice;
        }
    }
}
