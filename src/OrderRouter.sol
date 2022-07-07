// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.14;

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
import "../lib/interfaces/uniswap-v3/ISwapRouter.sol";
import "./test/utils/Console.sol";

contract OrderRouter {
    //----------------------Structs------------------------------------//

    /// @notice Struct to store important Dex specifications
    struct Dex {
        address factoryAddress;
        bytes32 initBytecode;
        bool isUniV2;
    }

    struct TokenToTokenExecutionPrice {
        uint128 aToWethReserve0;
        uint128 aToWethReserve1;
        uint128 wethToBReserve0;
        uint128 wethToBReserve1;
        uint256 price;
        address lpAddressAToWeth;
        address lpAddressWethToB;
    }

    struct TokenToWethExecutionPrice {
        uint128 aToWethReserve0;
        uint128 aToWethReserve1;
        uint256 price;
        address lpAddressAToWeth;
    }

    struct TokenToWethBatchOrder {
        uint256 amountIn;
        uint256 amountOutMin;
        address tokenIn;
        address lpAddress;
        address[] batchOwners;
        uint256[] ownerShares;
        bytes32[] orderIds;
    }

    struct TokenToTokenBatchOrder {
        uint256 amountIn;
        //TODO: need to set amount out min somewhere
        uint256 amountOutMin;
        address tokenIn;
        address tokenOut;
        address lpAddressAToWeth;
        address lpAddressWethToB;
        address[] batchOwners;
        uint256[] ownerShares;
        bytes32[] orderIds;
    }
    //----------------------State Variables------------------------------------//

    address owner;
    
    //----------------------State Structures------------------------------------//
    
    /// @notice Array of dex structures to be used throughout the contract for pair spot price calculations
    Dex[] public dexes;
    mapping(address => uint256) dexToIndex;

    struct SpotReserve {
        uint256 spotPrice;
        uint128 res0;
        uint128 res1;
    }

    //----------------------Constants------------------------------------//

    ISwapRouter public constant swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    //----------------------Modifiers------------------------------------//

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert MsgSenderIsNotOwner();
        }

        _;
    }

    //----------------------Constructor------------------------------------//

    constructor() {
        owner = msg.sender;
    }

    //----------------------Functions------------------------------------//

    /// @notice Helper function to calculate the logistic mapping output on a USDC input quantity for fee % calculation
    /// @dev calculation assumes 64x64 fixed point in128 representation for all values
    /// @param amountIn uint128 USDC amount in 64x64 fixed point to calculate the fee % of
    /// @return Out64x64 int128 Fee percent
    function _calculateFee(uint128 amountIn)
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
    function _calculateReward(uint128 percentFee, uint128 wethValue)
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

    /// @notice Helper function to calculate the max beacon reward for a group of order's
    /// @param reserve0SnapShot uint256 snapShotSpot of the lowest execution spot price of the whole batch
    /// @param reserve1SnapShot uint256 snapShotSpot of the lowest execution spot price of the whole batch
    /// @param reserve0 uint256 reserve0 of lp at execution time
    /// @param reserve1 uint256 reserve1 of lp at execution time
    /// @param fee uint256 lp fee
    /// @return maxReward uint256 maximum safe beacon reward to protect against flash loan price manipulation in the lp
    function _calculateMaxBeaconReward(
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
                    _calculateAlphaX(
                        reserve0SnapShot,
                        reserve1SnapShot,
                        reserve0,
                        reserve1
                    ) >> 64
                )
            );

            //TODO: do we need this?
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
    function _calculateAlphaX(
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

    /// @notice Add Dex struct to dexes array from arr _factory, and arr _hexDem
    /// @param _factory address[] dex factory address's to add
    /// @param _hexDem Factory address create2 deployment bytecode array
    /// @param isUniV2 Array of bool's indicating uniV2 status
    function addDex(
        address _factory,
        bytes32 _hexDem,
        bool isUniV2
    ) public onlyOwner {
        Dex memory _dex = Dex(_factory, _hexDem, isUniV2);
        dexes.push(_dex);
    }

    function _swapV2(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address reciever
    ) internal returns (uint256) {
        /// transfer the tokens to the lp
        IERC20(_tokenIn).transferFrom(reciever, _lp, _amountIn);

        //Sort the tokens
        (address token0, ) = _sortTokens(_tokenIn, _tokenOut);

        //Initialize the amount out depending on the token order
        (uint256 amount0Out, uint256 amount1Out) = _tokenIn == token0
            ? (uint256(0), _amountOutMin)
            : (_amountOutMin, uint256(0));

        ///@notice get the balance before
        uint256 balanceBefore = IERC20(_tokenOut).balanceOf(reciever);

        /// @notice Swap tokens for wrapped native tokens (nato).
        try
            IUniswapV2Pair(_lp).swap(
                amount0Out,
                amount1Out,
                reciever,
                new bytes(0)
            )
        {} catch {
            return 0;
        }

        ///@notice calculate the amount recieved
        uint256 amountRecieved = IERC20(_tokenOut).balanceOf(reciever) -
            balanceBefore;

        ///@notice if the amount recieved is less than the amount out min, revert
        if (amountRecieved < _amountOutMin) {
            revert InsufficientOutputAmount();
        }

        return amountRecieved;
    }

    ///@notice agnostic swap function that determines whether or not to swap on univ2 or univ3
    /// @param tokenIn address of the token being swapped out
    /// @param tokenOut address of the output token on the swap
    /// @param lpAddress lpAddress to be swapped on for uni v3
    /// @param amountIn amount of tokenIn to be swapped
    /// @param amountOutMin minimum amount out on the swap
    /// @return amountOut amount recieved post swap in tokenOut
    function _swap(
        address tokenIn,
        address tokenOut,
        address lpAddress,
        uint256 amountIn,
        uint256 amountOutMin,
        address reciever
    ) internal returns (uint256 amountOut) {
        if (_lpIsNotUniV3(lpAddress)) {
            amountOut = _swapV2(
                tokenIn,
                tokenOut,
                lpAddress,
                amountIn,
                amountOutMin,
                reciever
            );
        } else {
            amountOut = _swapV3(
                tokenIn,
                tokenOut,
                _getUniV3Fee(lpAddress),
                amountIn,
                amountOutMin,
                reciever
            );
        }
    }

    //TODO: swap with v3 lp not the router
    /// @notice Helper function to perform a swapExactInputSingle on Uniswap V3
    function _swapV3(
        address _tokenIn,
        address _tokenOut,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address reciever
    ) internal returns (uint256) {
        /// transfer the tokens to the contract
        IERC20(_tokenIn).transferFrom(reciever, address(this), _amountIn);

        //Aprove the tokens on the swap router
        IERC20(_tokenIn).approve(address(swapRouter), _amountIn);

        //Initialize swap parameters for the swap router
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams(
                _tokenIn,
                _tokenOut,
                _fee,
                reciever,
                block.timestamp + 5,
                _amountIn,
                _amountOutMin,
                0
            );

        /// @notice Swap tokens for wrapped native tokens (nato).
        try swapRouter.exactInputSingle(params) returns (uint256 _amountOut) {
            if (_amountOut < _amountOutMin) {
                return 0;
            }
            return _amountOut;
        } catch {
            return 0;
        }

        ///@notice calculate the amount recieved
        ///TODO: revisit this, if we should wrap this in an unchecked,
    }

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @param _factory bytes32 contract factory address
    /// @param _initBytecode bytes32 initialization bytecode for dex pair
    function _calculateV2SpotPrice(
        address token0,
        address token1,
        address _factory,
        bytes32 _initBytecode
    ) internal view returns (SpotReserve memory spRes, address poolAddress) {
        require(token0 != token1, "Invalid Token Pair, IDENTICAL Address's");
        (address tok0, address tok1) = _sortTokens(token0, token1);

        SpotReserve memory _spRes;

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
            return (_spRes, address(0));
        }

        //Set reserve0, reserve1 to current LP reserves
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pairAddress)
            .getReserves();

        (_spRes.res0, _spRes.res1) = (reserve0, reserve1);

        //Get target decimals for token0 & token1
        uint8 token0Decimals = _getTargetDecimals(tok0);
        uint8 token1Decimals = _getTargetDecimals(tok1);

        //Set common based reserve values
        (uint256 commonReserve0, uint256 commonReserve1) = _convertToCommonBase(
            reserve0,
            token0Decimals,
            reserve1,
            token1Decimals
        );
        unchecked {
            _spRes.spotPrice = ConveyorMath.div128x128(
                commonReserve0 << 128,
                commonReserve1 << 128
            );
            require(
                _spRes.spotPrice <=
                    0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            );
        }

        // Left shift commonReserve0 9 digits i.e. commonReserve0 = commonReserve0 * 2 ** 9
        (spRes, poolAddress) = (_spRes, pairAddress);
    }

   
    // function _getV3PairAddress(address token0, address token1)
    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @param amountIn amountIn to get out amount spot
    /// @param FEE lp fee
    /// @param tickSecond the tick second range to get the lp spot price from
    /// @param _factory Uniswap v3 factory address
    function _calculateV3SpotPrice(
        address token0,
        address token1,
        uint112 amountIn,
        uint24 FEE,
        uint32 tickSecond,
        address _factory
    ) internal view returns (SpotReserve memory, address) {
        SpotReserve memory _spRes;

        address pool;

        int24 tick;
        int56 tickCumulativesDelta;

        //Scope to prevent stack too deep error
        {
            //Pool address for token pair
            pool = IUniswapV3Factory(_factory).getPool(token0, token1, FEE);

            if (pool == address(0)) {
                return (_spRes, address(0));
            }

            unchecked {
                _spRes.res0 = uint128(IERC20(token0).balanceOf(pool));
                _spRes.res1 = uint128(IERC20(token1).balanceOf(pool));

                require(_spRes.res0 <= type(uint128).max);
                require(_spRes.res1 <= type(uint128).max);
            }

            {
                // int56 / uint32 = int24
                tick = getTick(pool, tickSecond);
            }
            //so if tickCumulativeDelta < 0 and division has remainder, then rounddown
            if (
                tickCumulativesDelta < 0 &&
                (tickCumulativesDelta % int32(1) != 0)
            ) {
                tick--;
            }
        }

        //amountOut = tick range spot over specified tick interval
        _spRes.spotPrice = _getQuoteAtTick(tick, amountIn, token0, token1);

        return (_spRes, pool);
    }

    function _lpIsNotUniV3(address lp) internal returns (bool) {
        bool success;
        assembly {
            //store the function sig for  "fee()"
            mstore(
                0x00,
                0xddca3f4300000000000000000000000000000000000000000000000000000000
            )

            success := call(
                gas(), // gas remaining
                lp, // destination address
                0, // no ether
                0x00, // input buffer (starts after the first 32 bytes in the `data` array)
                0x04, // input length (loaded from the first 32 bytes in the `data` array)
                0x00, // output buffer
                0x00 // output length
            )
        }
        ///@notice return the opposite of success, meaning if the call succeeded, the address is univ3, and we should
        ///@notice indicate that _lpIsNotUniV3 is false
        return !success;
    }

    function _getUniV3Fee(address lpAddress)
        internal
        view
        returns (uint24 fee)
    {
        return IUniswapV3Pool(lpAddress).fee();
    }

    function getTick(address pool, uint32 tickSecond)
        internal
        view
        returns (int24 tick)
    {
        int56 tickCumulativesDelta;
        //tickSeconds array defines our tick interval of observation over the lp
        uint32[] memory tickSeconds = new uint32[](2);
        //Populate tickSeconds array current block to tickSecond behind current block for tick range
        tickSeconds[0] = tickSecond;
        tickSeconds[1] = 0;

        {
            (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(
                tickSeconds
            );

            //Scope to prevent deep stack error
            //Spot price of tickSeconds ago - spot price of current block
            tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        }
        // int56 / uint32 = int24
        tick = int24(tickCumulativesDelta / (1));
    }

    /// @notice Helper to get all lps and prices across multiple dexes
    /// @param token0 address of token0
    /// @param token1 address of token1
    /// @param tickSecond tick second range on univ3
    /// @param FEE uniV3 fee
    function _getAllPrices(
        address token0,
        address token1,
        uint32 tickSecond,
        uint24 FEE
    )
        internal
        view
        returns (SpotReserve[] memory prices, address[] memory lps)
    {
        //Target base amount in value
        uint112 amountIn = _getTargetAmountIn(token0, token1);

        uint256 dexLength = dexes.length;

        SpotReserve[] memory _spotPrices = new SpotReserve[](dexes.length);
        address[] memory _lps = new address[](dexes.length);

        //Iterate through Dex's in dexes check if isUniV2 and accumulate spot price to meanSpotPrice
        for (uint256 i = 0; i < dexes.length; ++i) {
            // require(false, "Got here");
            if (dexes[i].isUniV2) {
                {
                    //Right shift spot price 9 decimals and add to meanSpotPrice
                    (
                        SpotReserve memory spotPrice,
                        address poolAddress
                    ) = _calculateV2SpotPrice(
                            token0,
                            token1,
                            dexes[i].factoryAddress,
                            dexes[i].initBytecode
                        );
                    if (spotPrice.spotPrice != 0) {
                        _spotPrices[i] = spotPrice;
                        _lps[i] = poolAddress;
                    }
                }
            } else {
                {
                    {
                        (
                            SpotReserve memory spotPrice,
                            address poolAddress
                        ) = _calculateV3SpotPrice(
                                token0,
                                token1,
                                amountIn,
                                FEE,
                                tickSecond,
                                dexes[i].factoryAddress
                            );
                        if (spotPrice.spotPrice != 0) {
                            _lps[i] = poolAddress;
                            _spotPrices[i] = spotPrice;
                        }
                    }
                }
            }
        }
        (prices, lps) = (_spotPrices, _lps);
    }

    //TODO: duplicate, remove this
    /// @notice Helper to get the lp fee from a v3 pair address
    /// @param pairAddress address of v3 lp pair
    /// @return poolFee uint24 fee of the pool
    function _getV3PoolFee(address pairAddress)
        internal
        view
        returns (uint24 poolFee)
    {
        poolFee = IUniswapV3Pool(pairAddress).fee();
    }

    /// @notice Helper to get amountIn amount for token pair
    function _getTargetAmountIn(address token0, address token1)
        internal
        view
        returns (uint112 amountIn)
    {
        //Get target decimals for token0, token1
        uint8 token0Target = _getTargetDecimals(token0); //18
        // require(false, "Got here");
        uint8 token1Target = _getTargetDecimals(token1); //6

        //target decimal := the difference in decimal targets between tokens
        uint8 targetDec = (token0Target < token1Target)
            ? (token1Target)
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
    function _convertToCommonBase(
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
    function _getTargetDecimals(address token)
        internal
        view
        returns (uint8 targetDecimals)
    {
        return IERC20(token).decimals();
    }

    /// @notice Helper function to return sorted token addresses
    function _sortTokens(address tokenA, address tokenB)
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

    /// @notice Given a tick and a token amount, calculates the amount of token received in exchange
    /// @param tick Tick value used to calculate the quote
    /// @param baseAmount Amount of token to be converted
    /// @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
    /// @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
    /// @return quoteAmount Amount of quoteToken received for baseAmount of baseToken
    function _getQuoteAtTick(
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
}
