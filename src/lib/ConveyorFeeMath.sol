// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./ConveyorMath.sol";
import "../../lib/libraries/QuadruplePrecision.sol";

library ConveyorFeeMath {
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
        unchecked {
            ///@notice This is to prevent over flow initialize the fee to fee+ (0.005-fee)/2+0.001*10**2
            if (percentFee <= ZERO_POINT_ZERO_ZERO_FIVE) {
                int256 innerPartial = int256(
                    uint256(ZERO_POINT_ZERO_ZERO_FIVE)
                ) - int128(percentFee);

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
        }

        return (conveyorReward, beaconReward);
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
