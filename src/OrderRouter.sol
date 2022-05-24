// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "../lib/interfaces/token/IERC20.sol";
// import "../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/ConveyorMath.sol";
import "./OrderBook.sol";
import "./test/utils/Console.sol";
import "../lib/libraries/Uniswap/FullMath.sol";
import "../lib/libraries/Uniswap/TickMath.sol";

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
    /// @param reserve0SnapShot uint256 snapShotSpot of the lowest execution spot price of the whole batch
    /// @param reserve1SnapShot uint256 snapShotSpot of the lowest execution spot price of the whole batch
    /// @param reserve0 uint256 reserve0 of lp at execution time
    /// @param reserve1 uint256 reserve1 of lp at execution time
    /// @param fee uint256 lp fee
    /// @return maxReward uint256 maximum safe beacon reward to protect against flash loan price manipulation in the lp
    function calculateMaxBeaconReward(
        uint128 reserve0SnapShot,
        uint128 reserve1SnapShot,
        uint128 reserve0,
        uint128 reserve1,
        uint128 fee
    ) public pure returns (uint128) {
        unchecked {
            uint128 maxReward = ConveyorMath.mul64x64(
                fee,
                uint128(
                    calculateAlphaX(
                        reserve0SnapShot,
                        reserve1SnapShot,
                        reserve0,
                        reserve1
                    ) >> 64
                )
            );
            require(maxReward <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
            return maxReward;
        }
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

    ) internal pure returns (uint256 alphaX) {


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

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @param _factory bytes32 contract factory address
    /// @param _initBytecode bytes32 initialization bytecode for dex pair
    /// @return spotPrice uint112 current reserve calculated spot price on dex pair
    function calculateV2SpotPrice(
        address token0,
        address token1,
        address _factory,
        bytes32 _initBytecode
    ) internal view returns (uint256 spotPrice) {
        require(token0 != token1, "Invalid Token Pair, IDENTICAL Address's");
        (address tok0, address tok1) = sortTokens(token0, token1);
        //Return Uniswap V2 Pair address
        address pairAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            _factory,
                            keccak256(abi.encodePacked(tok0, tok1)),
                            _initBytecode
                        )
                    )
                )
            )
        );

        require(pairAddress != address(0), "Invalid token pair");

        if (!(IUniswapV2Factory(_factory).getPair(tok0, tok1) == pairAddress)) {
            console.logString("Factory Address");
            console.log(IUniswapV2Factory(_factory).getPair(tok0, tok1));
            return 0;
        }

        //Set reserve0, reserve1 to current LP reserves
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pairAddress)
            .getReserves();

        //Get target decimals for token0 & token1
        uint8 token0Decimals = getTargetDecimals(tok0);
        uint8 token1Decimals = getTargetDecimals(tok1);

        //Set common based reserve values
        (uint256 commonReserve0, uint256 commonReserve1) = convertToCommonBase(
            reserve0,
            token0Decimals,
            reserve1,
            token1Decimals
        );

        // Left shift commonReserve0 9 digits i.e. commonReserve0 = commonReserve0 * 2 ** 9
        spotPrice = ((commonReserve0 << 9) / commonReserve1);
    }

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @return amountOut spot price of token1 with respect to token2 i.e reserve1/reserve2
    function calculateV3SpotPrice(
        address token0,
        address token1,
        uint112 amountIn,
        uint24 FEE,
        address _factory
    ) internal view returns (uint256) {
        //tickSeconds array defines our tick interval of observation over the lp
        uint32[] memory tickSeconds = new uint32[](2);
        //int32 version of tickSecond padding in tick range
        int32 tickSecondInt = int32(1);
        //Populate tickSeconds array current block to tickSecond behind current block for tick range
        tickSeconds[0] = 1;
        tickSeconds[1] = 0;

        //Pool address for token pair
        address pool = IUniswapV3Factory(_factory).getPool(token0, token1, FEE);

        if (pool == address(0)) {
            return 0;
        }
        //Start observation over lp in prespecified tick range
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(
            tickSeconds
        );

        //Spot price of tickSeconds ago - spot price of current block
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        // int56 / uint32 = int24
        int24 tick = int24(tickCumulativesDelta / (tickSecondInt));

        //so if tickCumulativeDelta < 0 and division has remainder, then rounddown
        if (
            tickCumulativesDelta < 0 &&
            (tickCumulativesDelta % tickSecondInt != 0)
        ) {
            tick--;
        }
        //amountOut = tick range spot over specified tick interval
        uint256 amountOut = getQuoteAtTick(tick, amountIn, token0, token1);

        return amountOut << 9;
    }

    /// @notice Helper function to get Mean spot price over multiple LP spot prices
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @param tickSecond uint32 tick seconds to calculate v3 price average over
    /// @param FEE LP token pair fee
    /// @return meanSpotPrice uint112 mean spot price over all dex's specified in input parameters
    function calculateMeanSpotPrice(
        address token0,
        address token1,
        uint32 tickSecond,
        uint24 FEE
    ) internal view returns (uint256) {
        //Initialize meanSpotPrice to 0
        uint256 meanSpotPrice = 0;
        uint8 incrementor = 0;
        //Target base amount in value
        uint112 amountIn = getTargetAmountIn(token0, token1);

        //Iterate through Dex's in dexes check if isUniV2 and accumulate spot price to meanSpotPrice
        for (uint256 i = 0; i < dexes.length; ++i) {
            if (dexes[i].isUniV2) {
                //Right shift spot price 9 decimals and add to meanSpotPrice
                uint256 spotPrice = calculateV2SpotPrice(
                    token0,
                    token1,
                    dexes[i].factoryAddress,
                    dexes[i].initBytecode
                );
                meanSpotPrice += spotPrice;

                incrementor += (spotPrice == 0) ? 0 : 1;
            } else {
                uint256 spotPrice = calculateV3SpotPrice(
                    token0,
                    token1,
                    amountIn,
                    FEE,
                    dexes[i].factoryAddress
                );
                meanSpotPrice += (spotPrice);
                incrementor += (spotPrice == 0) ? 0 : 1;
            }
        }

        return meanSpotPrice / incrementor;
    }

    /// @notice Helper to get amountIn amount for token pair
    function getTargetAmountIn(address token0, address token1)
        internal
        view
        returns (uint112 amountIn)
    {
        //Get target decimals for token0, token1
        uint8 token0Target = getTargetDecimals(token0);
        uint8 token1Target = getTargetDecimals(token1);

        //target decimal := the difference in decimal targets between tokens
        uint8 targetDec = (token0Target < token1Target)
            ? (token1Target - token0Target)
            : (token0Target - token1Target);

        //Set amountIn to correct target decimals
        amountIn = uint112(10**(targetDec));
    }

    /// @notice Helper function to change the base decimal value of token0 & token1 to the same target decimal value
    /// target decimal value for both token decimals to match will be max(token0Decimals, token1Decimals)
    /// @param reserve0 uint256 token1 value
    /// @param token0Decimals Decimals of token0
    /// @param reserve1 uint256 token2 value
    /// @param token1Decimals Decimals of token1
    function convertToCommonBase(
        uint256 reserve0,
        uint8 token0Decimals,
        uint256 reserve1,
        uint8 token1Decimals
    ) internal pure returns (uint256, uint256) {
        /// @dev Conditionally change the decimal to target := max(decimal0, decimal1)
        /// return tuple of modified reserve values in matching decimals
        if (token0Decimals > token1Decimals) {
            return (
                reserve0,
                reserve1 * (10**(token0Decimals - token1Decimals))
            );
        } else {
            return (
                reserve0 * (10**(token1Decimals - token0Decimals)),
                reserve1
            );
        }
    }

    /// @notice Helper function to get target decimals of ERC20 token
    /// @param token address of token to get target decimals
    /// @return targetDecimals uint8 target decimals of token
    function getTargetDecimals(address token)
        internal
        view
        returns (uint8 targetDecimals)
    {
        return IERC20(token).decimals();
    }

    /// @notice Helper function to return sorted token addresses
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

    /// @notice Helper function to get Min spot price over multiple LP spot prices
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @param tickSecond uint32 tick seconds to calculate v3 price average over
    /// @param FEE LP token pair fee
    /// @return meanSpotPrice uint112 mean spot price over all dex's specified in input parameters
    function calculateMinSpotPrice(
        address token0,
        address token1,
        uint32 tickSecond,
        uint24 FEE
    ) internal view returns (uint256) {
        //Initialize meanSpotPrice to 0
        uint256 minSpotPrice = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

        //Target base amount in value
        uint112 amountIn = getTargetAmountIn(token0, token1);

        //Iterate through Dex's in dexes check if isUniV2 and accumulate spot price to minSpotPrice
        for (uint256 i = 0; i < dexes.length; ++i) {
            if (dexes[i].isUniV2) {
                //Right shift spot price 9 decimals and add to meanSpotPrice
                uint256 spotPrice = calculateV2SpotPrice(
                    token0,
                    token1,
                    dexes[i].factoryAddress,
                    dexes[i].initBytecode
                );
                minSpotPrice = (spotPrice < minSpotPrice && spotPrice != 0)
                    ? spotPrice
                    : minSpotPrice;
            } else {
                uint256 spotPrice = calculateV3SpotPrice(
                    token0,
                    token1,
                    amountIn,
                    FEE,
                    dexes[i].factoryAddress
                );
                minSpotPrice = (spotPrice < minSpotPrice && spotPrice != 0)
                    ? spotPrice
                    : minSpotPrice;
            }
        }

        assert(
            minSpotPrice !=
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );
        return minSpotPrice;
    }

    /// @notice Given a tick and a token amount, calculates the amount of token received in exchange
    /// @param tick Tick value used to calculate the quote
    /// @param baseAmount Amount of token to be converted
    /// @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
    /// @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
    /// @return quoteAmount Amount of quoteToken received for baseAmount of baseToken
    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(
                sqrtRatioX96,
                sqrtRatioX96,
                1 << 64
            );
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    /// @notice Helper function to calculate transaction execution cost for the beacon
    /// @param token Address of token to estimate execution cost
    /// @param amount uint256 amount of token to estimate execution cost
    /// @param gas current oracle retrieved on chain gas price
    function calculateExecutionCost(
        address token,
        uint256 amount,
        uint256 gas
    ) internal pure returns (uint256 executionCost) {}

    /// @notice Helper function to calculate if transaction execution will be profitable for the beacon
    /// @param token Address of token to estimate execution cost
    /// @param amount uint256 amount of token to estimate execution cost
    /// @param gas current oracle retrieved on chain gas price
    /// @param beaconReward uint256 amount in wei rewarded to the beacon
    /// @return isProfitable bool indicating profitability of execution
    function calculateProfitability(
        address token,
        uint256 amount,
        uint256 gas,
        uint256 beaconReward
    ) internal pure returns (bool isProfitable) {}

    /// @notice Helper function to calculate beacon and conveyor reward on transaction execution
    /// @param percentFee uint8 percentage of order size to be taken from user order size
    /// @param wethValue uint256 total order value in wei at execution price
    /// @return conveyorReward conveyor reward in terms of wei
    /// @return beaconReward beacon reward in wei
    function calculateReward(uint8 percentFee, uint256 wethValue)
        internal
        pure
        returns (uint256 conveyorReward, uint256 beaconReward)
    {}
}
