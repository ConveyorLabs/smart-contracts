// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./ConveyorMath.sol";
import "./QuadruplePrecision.sol";

library ConveyorFeeMath {
    uint128 constant MIN_FEE_64x64 = 18446744073709552;
    uint128 constant MAX_UINT_128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint128 constant UNI_V2_FEE = 5534023222112865000;
    uint256 constant MAX_UINT_256 =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant ONE_128x128 = uint256(1) << 128;
    uint24 constant ZERO_UINT24 = 0;
    uint256 constant ZERO_POINT_NINE = 16602069666338597000 << 64;
    uint256 constant ONE_POINT_TWO_FIVE = 23058430092136940000 << 64;
    uint128 constant ZERO_POINT_ONE = 1844674407370955300;
    uint128 constant ZERO_POINT_ZERO_ZERO_FIVE = 92233720368547760;
    uint128 constant ZERO_POINT_ZERO_ZERO_ONE = 18446744073709550;
    uint128 constant MAX_CONVEYOR_PERCENT = 110680464442257300 * 10**2;
    uint128 constant MIN_CONVEYOR_PERCENT = 7378697629483821000;

    /// @notice Helper function to calculate beacon and conveyor reward on transaction execution.
    /// @param percentFee - Percentage of order size to be taken from user order size.
    /// @param wethValue - Total order value at execution price, represented in wei.
    /// @return conveyorReward - Conveyor reward, represented in wei.
    /// @return beaconReward - Beacon reward, represented in wei.
    function calculateReward(uint128 percentFee, uint128 wethValue)
        public
        pure
        returns (uint128 conveyorReward, uint128 beaconReward)
    {
        ///@notice Compute wethValue * percentFee
        uint256 totalWethReward = ConveyorMath.mul64I(
            percentFee,
            uint256(wethValue)
        );

        ///@notice Initialize conveyorPercent to hold conveyors portion of the reward
        uint128 conveyorPercent;

        ///@notice This is to prevent over flow initialize the fee to fee+ (0.005-fee)/2+0.001*10**2
        if (percentFee <= ZERO_POINT_ZERO_ZERO_FIVE) {
            int256 innerPartial = int256(uint256(ZERO_POINT_ZERO_ZERO_FIVE)) -
                int128(percentFee);

            conveyorPercent =
                (percentFee +
                    ConveyorMath.div64x64(
                        uint128(uint256(innerPartial)),
                        uint128(2) << 64
                    ) +
                    uint128(ZERO_POINT_ZERO_ZERO_ONE)) *
                10**2;
        } else {
            conveyorPercent = MAX_CONVEYOR_PERCENT;
        }

        if (conveyorPercent < MIN_CONVEYOR_PERCENT) {
            conveyorPercent = MIN_CONVEYOR_PERCENT;
        }

        ///@notice Multiply conveyorPercent by total reward to retrive conveyorReward
        conveyorReward = uint128(
            ConveyorMath.mul64I(conveyorPercent, totalWethReward)
        );

        beaconReward = uint128(totalWethReward) - conveyorReward;

        return (conveyorReward, beaconReward);
    }


    ///@notice Helper function to determine the proportional difference between two spot prices
    ///@param v3Spot - spotPrice from UniV3.
    ///@param v2Outlier - SpotPrice of the v2Outlier used to cross reference against the alphaXDivergenceThreshold.
    ///@return priceDivergence - Porportional difference between the v3Spot and v2Outlier
    function _calculatePriceDivergence(uint256 v3Spot, uint256 v2Outlier)
        public
        pure
        returns (uint256 priceDivergence)
    {
        ///@notice If the v3Spot equals the v2Outlier, there is no price divergence, so return 0.
        if (v3Spot == v2Outlier) {
            return 0;
        }

        uint256 proportionalSpotChange;

        ///@notice if the v3Spot is greater than the v2Outlier
        if (v3Spot > v2Outlier) {
            ///@notice Divide the v2Outlier by the v3Spot and subtract the result from 1.
            proportionalSpotChange = ConveyorMath.div128x128(v2Outlier, v3Spot);
            priceDivergence = ONE_128x128 - proportionalSpotChange;
        } else {
            ///@notice Divide the v3Spot by the v2Outlier and subtract the result from 1.
            proportionalSpotChange = ConveyorMath.div128x128(v3Spot, v2Outlier);
            priceDivergence = ONE_128x128 - proportionalSpotChange;
        }

        return priceDivergence;
    }

    /// @notice Helper function to calculate the max beacon reward for a group of orders
    /// @param reserve0 - Reserve0 of lp at execution time
    /// @param reserve1 - Reserve1 of lp at execution time
    /// @param fee - The fee to swap on the lp.
    /// @return maxReward - Maximum safe beacon reward to protect against flash loan price manipulation on the lp
    function _calculateMaxBeaconReward(
        uint256 delta,
        uint128 reserve0,
        uint128 reserve1,
        uint128 fee
    ) public pure returns (uint128) {
        uint128 maxReward = uint128(
            ConveyorMath.mul64I(
                fee,
                _calculateAlphaX(delta, reserve0, reserve1)
            )
        );
        return maxReward;
    }

    /// @notice Helper function to calculate the input amount needed to manipulate the spot price of the pool from snapShot to executionPrice
    /// @param reserve0Execution - snapShot of reserve0 at execution time
    /// @param reserve1Execution - snapShot of reserve1 at execution time
    /// @return alphaX - The input amount needed to manipulate the spot price of the respective lp to the amount delta.
    function _calculateAlphaX(
        uint256 delta,
        uint128 reserve0Execution,
        uint128 reserve1Execution
    ) internal pure returns (uint256) {
        ///@notice alphaX = (r1 * r0 - sqrtK * sqrtr0 * sqrt(delta * r1 + r1)) / r1
        uint256 _k = uint256(reserve0Execution) * reserve1Execution;
        bytes16 k = QuadruplePrecision.fromInt(int256(_k));
        bytes16 sqrtK = QuadruplePrecision.sqrt(k);
        bytes16 deltaQuad = QuadruplePrecision.from128x128(int256(delta));
        bytes16 reserve1Quad = QuadruplePrecision.fromUInt(reserve1Execution);
        bytes16 reserve0Quad = QuadruplePrecision.fromUInt(reserve0Execution);
        bytes16 numeratorPartial = QuadruplePrecision.add(
            QuadruplePrecision.mul(deltaQuad, reserve1Quad),
            reserve1Quad
        );
        bytes16 sqrtNumPartial = QuadruplePrecision.sqrt(numeratorPartial);
        bytes16 sqrtReserve0 = QuadruplePrecision.sqrt(reserve0Quad);
        bytes16 numerator = QuadruplePrecision.abs(
            QuadruplePrecision.sub(
                k,
                QuadruplePrecision.mul(
                    sqrtReserve0,
                    QuadruplePrecision.mul(sqrtNumPartial, sqrtK)
                )
            )
        );
        uint256 alphaX = uint256(
            QuadruplePrecision.toUInt(
                QuadruplePrecision.div(numerator, reserve1Quad)
            )
        );

        return alphaX;
    }


    ///@notice Helper function to derive the token pair address on a Dex from the factory address and initialization bytecode.
    ///@param _factory - Factory address of the Dex.
    ///@param token0 - Token0 address.
    ///@param token1 - Token1 address.
    ///@param _initBytecode - Initialization bytecode of the factory contract.
    function _getV2PairAddress(
        address _factory,
        address token0,
        address token1,
        bytes32 _initBytecode
    ) internal pure returns (address pairAddress) {
        pairAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            _factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            _initBytecode
                        )
                    )
                )
            )
        );
    }


    /// @notice Helper function to return sorted token addresses.
    /// @param tokenA - Address of tokenA.
    /// @param tokenB - Address of tokenB.
    function _sortTokens(address tokenA, address tokenB)
        public
        pure
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

}