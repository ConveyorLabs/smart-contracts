// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "../lib/interfaces/token/IERC20.sol";
// import "../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
// import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
// import "../lib/libraries/uniswap/OracleLibrary.sol";
// import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
// import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/PriceLibrary.sol";
import "../lib/libraries/ConveyorMath.sol";
import "./OrderBook.sol";
import "./test/utils/Console.sol";

contract OrderRouter {
    //----------------------Constructor------------------------------------//

    //----------------------Errors------------------------------------//
    error InsufficientOutputAmount();

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
        internal
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
        internal
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
    function calculateFee(uint128 amountIn)
        internal
        pure
        returns (uint128 Out64x64)
    {
        require(
            !(amountIn << 64 > 0xfffffffffffffffffffffffffff),
            "Overflow Error"
        );
        uint128 iamountIn = amountIn << 64;
        uint128 numerator = 16602069666338597000; //.9 sccale := 1e19 ==> 64x64 fixed representation
        uint128 denominator = (23058430092136940000 +
            ConveyorMath.exp(ConveyorMath.div64x64(iamountIn, 75000 << 64)));
        uint128 rationalFraction = ConveyorMath.div64x64(
            numerator,
            denominator
        );
        Out64x64 = (rationalFraction + 1844674407370955300) / 10**2;
    }

    /// @notice Helper function to calculate beacon and conveyor reward on transaction execution
    /// @param percentFee uint8 percentage of order size to be taken from user order size
    /// @param wethValue uint256 total order value in wei at execution price
    /// @return conveyorReward conveyor reward in terms of wei
    /// @return beaconReward beacon reward in wei
    function calculateReward(uint128 percentFee, uint128 wethValue)
        internal
        pure
        returns (uint128 conveyorReward, uint128 beaconReward)
    {
        uint128 conveyorPercent = (percentFee +
            ConveyorMath.div64x64(
                92233720368547760 - percentFee,
                uint128(2) << 64
            ) +
            uint128(18446744073709550)) * 10**2;
        uint128 beaconPercent = (uint128(1) << 64) - conveyorPercent;

        conveyorReward = ConveyorMath.mul64x64(
            ConveyorMath.mul64x64(percentFee, wethValue),
            conveyorPercent
        );
        beaconReward = ConveyorMath.mul64x64(
            ConveyorMath.mul64x64(percentFee, wethValue),
            beaconPercent
        );

        return (conveyorReward, beaconReward);
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

    /// @notice Helper function to calculate the input amount needed to manipulate the spot price of the pool from snapShot to executionPrice
    /// @param reserve0SnapShot snapShot of reserve0 at snapShot time
    /// @param reserve1SnapShot snapShot of reserve1 at snapShot time
    /// @param reserve0Execution snapShot of reserve0 at snapShot time
    /// @param reserve1Execution snapShot of reserve1 at snapShot time
    /// @return alphaX alphaX amount to manipulate the spot price of the respective lp to execution trigger
    function calculateAlphaX(
        uint128 reserve0SnapShot,
        uint128 reserve1SnapShot,
        uint128 reserve0Execution,
        uint128 reserve1Execution
    ) internal view returns (uint256 alphaX) {
        //Store execution spot price in int128 executionSpot
        uint128 executionSpot = ConveyorMath.div64x64(
            reserve0Execution,
            reserve1Execution
        );

        //Store snapshot spot price in int128 snapshotSpot
        uint128 snapShotSpot = ConveyorMath.div64x64(
            reserve0SnapShot,
            reserve1SnapShot
        );

        //Store difference proportional difference between executionSpot and snapShotSpot in int128 delta
        uint128 delta = uint128(
            ConveyorMath.abs(
                int128(ConveyorMath.div64x64(executionSpot, snapShotSpot)) -
                    (1 << 64)
            )
        );

        //Store k=reserve0SnapShot*reserve1SnapShot in int256 k
        uint256 k = uint256(
            ConveyorMath.mul64x64(reserve0SnapShot, reserve1SnapShot)
        ) << 64;

        //Store sqrt k in sqrtK int128
        uint128 sqrtK = ConveyorMath.sqrtu(k);

        //Store sqrt of reserve0SnapShot in sqrtReserve0Snap
        uint128 sqrtReserve0Snap = ConveyorMath.sqrtu(
            uint256(reserve0SnapShot) << 64
        );

        //sqrtNumPartial := sqrt(delta*r_y+r_y)
        uint128 sqrtNumPartial = ConveyorMath.sqrtu(
            uint256(
                ConveyorMath.mul64x64(delta, reserve1SnapShot) +
                    reserve1SnapShot
            ) << 64
        );

        //Full numerator in numerator uint256 of alphaX fraction ==> sqrt(k)*sqrt(r_x)*sqrt(delta*r_y+r_y)-k
        uint256 numerator = (uint256(
            ConveyorMath.mul64x64(
                ConveyorMath.mul64x64(sqrtK, sqrtReserve0Snap),
                sqrtNumPartial
            )
        ) << 64) - k;

        alphaX = ConveyorMath.div128x128(
            numerator,
            (uint256(reserve1SnapShot) << 64)
        );
    }

    //------------------------Admin Functions----------------------------

    //TODO: add onlyOwner
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

    function _swapV2(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint256 _amountIn,
        uint256 _amountOutMin
    ) internal returns (uint256) {
        /// transfer the tokens to the lp
        IERC20(_tokenIn).transferFrom(msg.sender, _lp, _amountIn);

        //Sort the tokens
        (address token0, ) = sortTokens(_tokenIn, _tokenOut);

        //Initialize the amount out depending on the token order
        (uint256 amount0Out, uint256 amount1Out) = _tokenIn == token0
            ? (uint256(0), _amountOutMin)
            : (_amountOutMin, uint256(0));

        ///@notice get the balance before
        uint256 balanceBefore = IERC20(_tokenOut).balanceOf(address(this));

        /// @notice Swap tokens for wrapped native tokens (nato).
        IUniswapV2Pair(_lp).swap(
            amount0Out,
            amount1Out,
            address(this),
            new bytes(0)
        );

        ///@notice calculate the amount recieved
        uint256 amountRecieved = IERC20(_tokenOut).balanceOf(address(this)) -
            balanceBefore;

        ///@notice if the amount recieved is less than the amount out min, revert
        if (amountRecieved >= _amountOutMin) {
            revert InsufficientOutputAmount();
        }

        return amountRecieved;
    }

    function _swapV3() internal {}

    /// @notice Returns sorted token addresses, used to handle return values from pairs sorted in this order. Code from the univ2library.
    function sortTokens(address tokenA, address tokenB)
        internal
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
