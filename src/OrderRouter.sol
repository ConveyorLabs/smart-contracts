// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

// import "../lib/interfaces/token/IERC20.sol";
// import "../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
// import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
// import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
// import "../lib/libraries/uniswap/OracleLibrary.sol";
// import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
// import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/PriceLibrary.sol";
import "../lib/libraries/ConveyorMath64x64.sol";
import "./OrderBook.sol";
import "../lib/AggregatorV3Interface.sol";

contract OrderRouter {
    //----------------------Constructor------------------------------------//

    //----------------------Structs------------------------------------//

    /// @notice Struct to store important Dex specifications
    struct Dex {
        address factoryAddress;
        bytes32 initBytecode;
        bool isUniV2;
    }

    //----------------------State Structures------------------------------------//

    /// @notice Array of dex structures to be used throughout the contract for pair spot price calculations
    Dex[] public dexes;

    //----------------------Functions------------------------------------//

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token0
    /// @param token1 bytes32 address of token1
    /// @return uint256 spot price of token1 with respect to token2 i.e reserve1/reserve2
    function calculateMeanPairSpotPrice(address token0, address token1)
        external
        view
        returns (uint256)
    {
        return
            PriceLibrary.calculateMeanSpotPrice(token0, token1, dexes, 1, 3000);
    }

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @return uint256 spot price of token1 with respect to token2 i.e reserve1/reserve2
    function calculateMinPairSpotPrice(address token0, address token1)
        external
        view
        returns (uint256)
    {
        return
            PriceLibrary.calculateMinSpotPrice(token0, token1, dexes, 1, 3000);
    }

    /// @notice Helper function to calculate the logistic mapping output on a USDC input quantity for fee % calculation
    /// @dev calculation assumes 64x64 fixed point in128 representation for all values
    /// @param amountIn uint128 USDC amount in 64x64 fixed point to calculate the fee % of
    /// @return Out64x64 int128 Fee percent
    function calculateFee(int128 amountIn)
        public
        pure
        returns (int128 Out64x64)
    {
        require(
            !(amountIn << 64 > 0xfffffffffffffffffffffffffff),
            "Overflow Error"
        );
        int128 iamountIn = amountIn << 64;
        int128 numerator = 16602069666338597000; //.9 sccale := 1e19 ==> 64x64 fixed representation
        int128 denominator = (23058430092136940000 +
            ConveyorMath64x64.exp(
                ConveyorMath64x64.div(iamountIn, 75000 << 64)
            ));
        int128 rationalFraction = ConveyorMath64x64.div(numerator, denominator);
        Out64x64 = rationalFraction + 1844674407370955300;
    }

    /// @notice Helper function to calculate beacon and conveyor reward on transaction execution
    /// @param percentFee uint8 percentage of order size to be taken from user order size
    /// @param wethValue uint256 total order value in wei at execution price
    /// @return conveyorReward conveyor reward in terms of wei
    /// @return beaconReward beacon reward in wei
    function calculateReward(int128 percentFee, int128 wethValue)
        public
        pure
        returns (int128 conveyorReward, int128 beaconReward)
    {
        /// Todo calculate the beaconReward/conveyorReward based on applying percentFee to wethValue
    }

    /// @notice Helper function to check if min credits needed for order placement are satisfied
    /// @param orderGroup := array of order's to be placed
    /// @param gasPrice uint256 in gwei
    /// @return bool := boolean value indicating whether gas credit's provide coverage over all orders in the orderGroup
    function hasMinGasCredits(
        OrderBook.Order[] calldata orderGroup,
        uint256 gasPrice
    ) internal pure returns (bool) {
        /// Todo iterate through each order in orderGroup, check if gas credits is satisfied for each order
    }

    /// @notice Helper function to calculate min gas credit quantity for singular order
    /// @param order Order struct to be checked for minimum gas credits
    /// @param gasPrice uint256 in gwei
    /// @return minCredits uint256 minimum gas credits required represented in wei
    function calculateMinGasCredits(
        OrderBook.Order calldata order,
        uint256 gasPrice
    ) internal pure returns (uint256) {
        /// Todo determine the execution cost based on gasPrice, and return minimum gasCredits required in wei for order placement
    }

    /// @notice Helper function to calculate the max beacon reward for a group of order's
    /// @param snapShotSpot uint256 snapShotSpot of the lowest execution spot price of the whole batch
    /// @param reserve0 uint256 reserve0 of lp at execution time
    /// @param reserve1 uint256 reserve1 of lp at execution time
    /// @param fee uint256 lp fee
    /// @return maxBeaconReward uint256 maximum safe beacon reward to protect against flash loan price manipulation in the lp
    function calculateMaxBeaconReward(
        uint256 snapShotSpot,
        uint256 reserve0,
        uint256 reserve1,
        uint8 fee
    ) internal pure returns (uint256) {
        /// Todo calulate alphaX and multiply by fee to determine max beacon reward quantity
    }

    //------------------------Admin Functions----------------------------

    /// @notice Add Dex struct to dexes array from arr _factory, and arr _hexDem
    /// @param _factory address[] dex factory address's to add
    /// @param _hexDem Factory address create2 deployment bytecode array
    /// @param isUniV2 Array of bool's indicating uniV2 status
    function addDex(
        address[] memory _factory,
        bytes32[] memory _hexDem,
        bool[] memory isUniV2
    ) public {
        require(
            (_factory.length == _hexDem.length &&
                _hexDem.length == isUniV2.length),
            "Invalid input, Arr length mismatch"
        );
        for (uint256 i = 0; i < _factory.length; i++) {
            Dex memory d = Dex(_factory[i], _hexDem[i], isUniV2[i]);
            dexes.push(d);
        }
    }
}
