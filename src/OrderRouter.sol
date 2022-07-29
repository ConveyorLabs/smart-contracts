// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

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
import "../lib/interfaces/token/IWETH.sol";
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
        uint8[] decimalsInDecimalsAToWeth;
        uint128 wethToBReserve0;
        uint128 wethToBReserve1;
        uint8[] decimalsInDecimalsWethToB;
        uint256 price;
        address lpAddressAToWeth;
        address lpAddressWethToB;
    }

    struct TokenToWethExecutionPrice {
        uint128 aToWethReserve0;
        uint128 aToWethReserve1;
        uint8[] decimalsInDecimalsAToWeth;
        uint256 price;
        address lpAddressAToWeth;
    }

    struct TokenToWethBatchOrder {
        uint256 batchLength;
        uint256 amountIn;
        uint256 amountOutMin;
        address tokenIn;
        address lpAddress;
        address[] batchOwners;
        uint256[] ownerShares;
        bytes32[] orderIds;
    }

    struct TokenToTokenBatchOrder {
        uint256 batchLength;
        uint256 amountIn;
        uint256 amountOutMin;
        address tokenIn;
        address tokenOut;
        address lpAddressAToWeth;
        address lpAddressWethToB;
        address[] batchOwners;
        uint256[] ownerShares;
        bytes32[] orderIds;
    }

    struct SpotReserve {
        uint256 spotPrice;
        uint128 res0;
        uint128 res1;
        bool token0IsReserve0;
        uint8[] tokenInTokenOutCommonDecimals;
    }

    //----------------------State Variables------------------------------------//

    address owner;

    //----------------------State Structures------------------------------------//

    /// @notice Array of dex structures to be used throughout the contract for pair spot price calculations
    Dex[] public dexes;

    mapping(address => uint256) dexToIndex;

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

    constructor(
        bytes32[] memory _deploymentByteCodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2
    ) {
        for (uint256 i = 0; i < _deploymentByteCodes.length; ++i) {
            dexes.push(
                Dex({
                    factoryAddress: _dexFactories[i],
                    initBytecode: _deploymentByteCodes[i],
                    isUniV2: _isUniV2[i]
                })
            );
        }

        owner = msg.sender;
    }

    //----------------------Functions------------------------------------//

    function safeTransferETH(address to, uint256 amount) public {
        bool success;

        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }
        require(success, "ETH_TRANSFER_FAILED");
    }

    /// @notice Helper function to calculate the logistic mapping output on a USDC input quantity for fee % calculation
    /// @dev calculation assumes 64x64 fixed point in128 representation for all values
    /// @param amountIn uint128 USDC amount in 64x64 fixed point to calculate the fee % of
    /// @return Out64x64 int128 Fee percent
    function _calculateFee(
        uint128 amountIn,
        address usdc,
        address weth
    ) internal view returns (uint128) {
        uint128 Out64x64;

        (SpotReserve memory _spRes, ) = _calculateV2SpotPrice(
            weth,
            usdc,
            dexes[0].factoryAddress,
            dexes[0].initBytecode
        );
        uint256 spotPrice = _spRes.spotPrice;

        uint256 amountInUsdcDollarValue = ConveyorMath.mul128I(
            spotPrice,
            amountIn
        ) / uint256(10**18);
        if (amountInUsdcDollarValue >= 1000000) {
            Out64x64 = 18446744073709552;
            return Out64x64;
        }

        uint256 numerator = 16602069666338597000 << 64; // 128x128 fixed representation

        uint128 exponent = uint128(
            ConveyorMath.divUI(amountInUsdcDollarValue, 75000)
        );

        if (exponent >= 0x400000000000000000) {
            Out64x64 = 18446744073709552;
            return Out64x64;
        }
        uint256 denominator = ConveyorMath.add128x128(
            23058430092136940000 << 64,
            uint256(ConveyorMath.exp(exponent)) << 64
        );
        uint256 rationalFraction = ConveyorMath.div128x128(
            numerator,
            denominator
        );

        Out64x64 = ConveyorMath.div64x64(
            ConveyorMath.add64x64(
                uint128(rationalFraction >> 64),
                1844674407370955300
            ),
            uint128(100 << 64)
        );

        return Out64x64;
    }

    /// @notice Helper function to calculate beacon and conveyor reward on transaction execution
    /// @param percentFee uint8 percentage of order size to be taken from user order size
    /// @param wethValue uint256 total order value in wei at execution price
    /// @return conveyorReward conveyor reward in terms of wei
    /// @return beaconReward beacon reward in wei
    function _calculateReward(uint128 percentFee, uint128 wethValue)
        internal
        view
        returns (uint128 conveyorReward, uint128 beaconReward)
    {
        uint256 totalWethReward = ConveyorMath.mul64I(
            percentFee,
            uint256(wethValue)
        );
        
        uint128 conveyorPercent;
        
        if (percentFee <= 92233720368547760) {
            int256 innerPartial = int256(92233720368547760)-int128(percentFee);
            
            conveyorPercent =
                (percentFee +
                    ConveyorMath.div64x64(
                        uint128(uint256(innerPartial)),
                        uint128(2) << 64
                    ) +
                    uint128(18446744073709550)) *
                10**2;
        } else {
            conveyorPercent = 110680464442257300;
        }

        if (conveyorPercent < 7378697629483821000) {
            conveyorPercent = 7583661452525017000;
        }
        
        conveyorReward= uint128(
            ConveyorMath.mul64I(conveyorPercent, totalWethReward)
        );

        beaconReward = uint128(totalWethReward) - conveyorReward;

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
                _calculateAlphaX(
                    reserve0SnapShot,
                    reserve1SnapShot,
                    reserve0,
                    reserve1
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
    ) internal pure returns (uint128 alphaX) {
        //k = rx*ry
        uint256 k = uint256(reserve0SnapShot) * reserve1SnapShot;

        //sqrt(k) 64.64 form
        uint256 sqrtK128x128 = ConveyorMath.sqrt128x128(k << 128);

        //sqrt(rx)
        uint256 sqrtReserve0SnapShot128x128 = ConveyorMath.sqrt128x128(
            uint256(reserve0SnapShot) << 128
        );

        //Delta change in spot prices from snapshot-> execution
        uint256 delta;
        delta = ConveyorMath.div128x128(
            ConveyorMath.div128x128(
                uint256(reserve0SnapShot) << 128,
                uint256(reserve1SnapShot) << 128
            ),
            ConveyorMath.div128x128(
                uint256(reserve0Execution) << 128,
                uint256(reserve1Execution) << 128
            )
        );

        if (delta > uint256(1) << 128) {
            delta = delta - (uint256(1) << 128);
        } else {
            delta = (uint256(1) << 128) - delta;
        }

        uint256 numeratorPartial128x128 = ConveyorMath.sqrt128x128(
            ConveyorMath.add128x128(
                ConveyorMath.mul128x64(
                    uint256(reserve1SnapShot) << 128,
                    uint128(delta >> 64)
                ),
                uint256(reserve1SnapShot) << 128
            )
        );

        uint128 numerator128x128 = ConveyorMath.sub64UI(
            ConveyorMath.mul64x64(
                uint128(numeratorPartial128x128 >> 64),
                ConveyorMath.mul64x64(
                    uint128(sqrtK128x128 >> 64),
                    uint128(sqrtReserve0SnapShot128x128 >> 64)
                )
            ),
            (k)
        );

        alphaX = ConveyorMath.div64x64(
            numerator128x128,
            uint128(reserve1SnapShot) << 64
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
        address _reciever,
        address sender
    ) internal returns (uint256) {
        /// transfer the tokens to the lp
        IERC20(_tokenIn).transferFrom(sender, _lp, _amountIn);

        //Sort the tokens
        (address token0, ) = _sortTokens(_tokenIn, _tokenOut);

        //Initialize the amount out depending on the token order
        (uint256 amount0Out, uint256 amount1Out) = _tokenIn == token0
            ? (uint256(0), _amountOutMin)
            : (_amountOutMin, uint256(0));

        ///@notice get the balance before
        uint256 balanceBefore = IERC20(_tokenOut).balanceOf(_reciever);

        /// @notice Swap tokens for wrapped native tokens (nato).
        try
            IUniswapV2Pair(_lp).swap(
                amount0Out,
                amount1Out,
                _reciever,
                new bytes(0)
            )
        {
            console.logString("Passed v2 swap");
        } catch {
            console.log("Failed v2");
            //TODO: emit an event for the error that happened
            return 0;
        }

        ///@notice calculate the amount recieved
        uint256 amountRecieved = IERC20(_tokenOut).balanceOf(_reciever) -
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
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMin,
        address reciever,
        address sender
    ) internal returns (uint256 amountOut) {
        if (_lpIsNotUniV3(lpAddress)) {
            amountOut = _swapV2(
                tokenIn,
                tokenOut,
                lpAddress,
                amountIn,
                amountOutMin,
                reciever,
                sender
            );
        } else {
            amountOut = _swapV3(
                tokenIn,
                tokenOut,
                fee,
                amountIn,
                amountOutMin,
                reciever,
                sender
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
        address reciever,
        address sender
    ) internal returns (uint256) {
        /// transfer the tokens to the contract
        if (sender != address(this)) {
            IERC20(_tokenIn).transferFrom(sender, address(this), _amountIn);
        }

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
            console.logString("Passed V3 Swap");

            return _amountOut;
        } catch {
            console.logString("Failed V3 swap");
            return 0;
        }

        ///@notice calculate the amount recieved
        ///TODO: revisit this, if we should wrap this in an uncheck_getTargetAmountIned,
    }

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @param _factory bytes32 contract factory address
    /// @param _initBytecode bytes32 initialization bytecode for dex pair
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
        address tok0;
        address tok1;

        {
            (tok0, tok1) = _sortTokens(token0, token1);
        }
        SpotReserve memory _spRes;

        //Return Uniswap V2 Pair address
        address pairAddress = _getV2PairAddress(
            _factory,
            tok0,
            tok1,
            _initBytecode
        );

        require(pairAddress != address(0), "Invalid token pair");

        if (!(IUniswapV2Factory(_factory).getPair(tok0, tok1) == pairAddress)) {
            return (_spRes, address(0));
        }
        {
            //Set reserve0, reserve1 to current LP reserves
            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pairAddress)
                .getReserves();

            //Set common based reserve values
            (
                uint256 commonReserve0,
                uint256 commonReserve1,
                uint8[] memory alphaXDecimalsDecimalsCommon
            ) = _getReservesCommonDecimals(
                    token0,
                    tok0,
                    tok1,
                    reserve0,
                    reserve1
                );

            _spRes.tokenInTokenOutCommonDecimals = alphaXDecimalsDecimalsCommon;

            if (token0 == tok0) {
                _spRes.spotPrice = ConveyorMath.div128x128(
                    commonReserve1 << 128,
                    commonReserve0 << 128
                );
                _spRes.token0IsReserve0 = true;

                (_spRes.res0, _spRes.res1) = (
                    uint128(commonReserve0),
                    uint128(commonReserve1)
                );
            } else {
                _spRes.spotPrice = ConveyorMath.div128x128(
                    commonReserve0 << 128,
                    commonReserve1 << 128
                );
                _spRes.token0IsReserve0 = false;

                (_spRes.res1, _spRes.res0) = (
                    uint128(commonReserve0),
                    uint128(commonReserve1)
                );
            }

            require(
                _spRes.spotPrice <=
                    0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            );
        }

        // Left shift commonReserve0 9 digits i.e. commonReserve0 = commonReserve0 * 2 ** 9
        (spRes, poolAddress) = (_spRes, pairAddress);
    }

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

    function _getReservesCommonDecimals(
        address token0,
        address tok0,
        address tok1,
        uint128 reserve0,
        uint128 reserve1
    )
        internal
        view
        returns (
            uint128,
            uint128,
            uint8[] memory
        )
    {
        //Get target decimals for token0 & token1
        uint8 token0Decimals = _getTargetDecimals(tok0);
        uint8 token1Decimals = _getTargetDecimals(tok1);
        uint8[] memory tokenInCommon = new uint8[](2);
        tokenInCommon[0] = token0 == tok0 ? token0Decimals : token1Decimals;

        //Set common based reserve values
        (
            uint128 commonReserve0,
            uint128 commonReserve1,
            uint8 commonDecimals
        ) = _convertToCommonBase(
                reserve0,
                token0Decimals,
                reserve1,
                token1Decimals
            );
        tokenInCommon[1] = commonDecimals;
        return (commonReserve0, commonReserve1, tokenInCommon);
    }

    function _getReservesCommonDecimalsV3(
        address token0,
        address token1,
        uint128 reserve0,
        uint128 reserve1,
        address pool
    )
        internal
        view
        returns (
            uint128,
            uint128,
            bool token0IsReserve0,
            uint8[] memory
        )
    {
        //Get target decimals for token0 & token1
        uint8 token0Decimals = _getTargetDecimals(token0);
        uint8 token1Decimals = _getTargetDecimals(token1);

        address TOKEN0 = IUniswapV3Pool(pool).token0();

        token0IsReserve0 = TOKEN0 == token0 ? true : false;
        if (token0IsReserve0) {
            //Set common based reserve values
            (
                uint128 commonReserve0,
                uint128 commonReserve1,
                uint8 commonDecimals
            ) = _convertToCommonBase(
                    reserve0,
                    token0Decimals,
                    reserve1,
                    token1Decimals
                );
            uint8[] memory decimalsInDecimalsCommon = new uint8[](2);
            decimalsInDecimalsCommon[0] = token0Decimals;
            decimalsInDecimalsCommon[1] = commonDecimals;
            return (
                commonReserve0,
                commonReserve1,
                token0IsReserve0,
                decimalsInDecimalsCommon
            );
        } else {
            //Set common based reserve values
            (
                uint128 commonReserve0,
                uint128 commonReserve1,
                uint8 commonDecimals
            ) = _convertToCommonBase(
                    reserve0,
                    token1Decimals,
                    reserve1,
                    token0Decimals
                );
            uint8[] memory decimalsInDecimalsCommon = new uint8[](2);
            decimalsInDecimalsCommon[0] = token1Decimals;
            decimalsInDecimalsCommon[1] = commonDecimals;
            return (
                commonReserve1,
                commonReserve0,
                token0IsReserve0,
                decimalsInDecimalsCommon
            );
        }
    }

    // function _getV3PairAddress(address token0, address token1)
    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @param amountIn amountIn to get out amount spot
    /// @param fee lp fee
    /// @param tickSecond the tick second range to get the lp spot price from
    /// @param _factory Uniswap v3 factory address
    function _calculateV3SpotPrice(
        address token0,
        address token1,
        uint112 amountIn,
        uint24 fee,
        uint32 tickSecond,
        address _factory
    ) internal view returns (SpotReserve memory, address) {
        SpotReserve memory _spRes;

        address pool;
        int24 tick;

        //Scope to prevent stack too deep error
        {
            //Pool address for token pair
            pool = IUniswapV3Factory(_factory).getPool(token0, token1, fee);

            if (pool == address(0)) {
                return (_spRes, address(0));
            }

            uint128 reserve0 = uint128(IERC20(token0).balanceOf(pool));
            uint128 reserve1 = uint128(IERC20(token1).balanceOf(pool));

            (
                _spRes.res0,
                _spRes.res1,
                _spRes.token0IsReserve0,
                _spRes.tokenInTokenOutCommonDecimals
            ) = _getReservesCommonDecimalsV3(
                token0,
                token1,
                reserve0,
                reserve1,
                pool
            );
            {
                // int56 / uint32 = int24
                tick = _getTick(pool, tickSecond);
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

    function _getUniV3Fee(address lpAddress) internal returns (uint24 fee) {
        if (!_lpIsNotUniV3(lpAddress)) {
            return IUniswapV3Pool(lpAddress).fee();
        } else {
            return uint24(0);
        }
    }

    function _getTick(address pool, uint32 tickSecond)
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

            tick = int24(tickCumulativesDelta / int32(tickSecond));

            if (
                tickCumulativesDelta < 0 &&
                (tickCumulativesDelta % int32(tickSecond) != 0)
            ) tick--;
        }
        // int56 / uint32 = int24
        return tick;
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
        if (token0 != token1) {
            //Target base amount in value
            // uint112 amountIn = _getTargetAmountIn(token0, token1);
            uint112 amountIn = _getGreatestTokenDecimalsAmountIn(
                token0,
                token1
            );

            SpotReserve[] memory _spotPrices = new SpotReserve[](dexes.length);
            address[] memory _lps = new address[](dexes.length);

            //Iterate through Dex's in dexes check if isUniV2 and accumulate spot price to meanSpotPrice
            for (uint256 i = 0; i < dexes.length; ++i) {
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

            return (_spotPrices, _lps);
        } else {
            SpotReserve[] memory _spotPrices = new SpotReserve[](dexes.length);
            address[] memory _lps = new address[](dexes.length);
            return (_spotPrices, _lps);
        }
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
    function _getGreatestTokenDecimalsAmountIn(address token0, address token1)
        internal
        view
        returns (uint112 amountIn)
    {
        //Get target decimals for token0, token1
        uint8 token0Target = _getTargetDecimals(token0); //18
        uint8 token1Target = _getTargetDecimals(token1); //6

        //target decimal := the difference in decimal targets between tokens
        uint8 targetDec = (token0Target < token1Target)
            ? (token1Target)
            : (token0Target);

        //Set amountIn to correct target decimals
        amountIn = uint112(10**targetDec);
    }

    /// @notice Helper function to change the base decimal value of token0 & token1 to the same target decimal value
    /// target decimal value for both token decimals to match will be max(token0Decimals, token1Decimals)
    /// @param reserve0 uint256 token1 value
    /// @param token0Decimals Decimals of token0
    /// @param reserve1 uint256 token2 value
    /// @param token1Decimals Decimals of token1
    function _convertToCommonBase(
        uint128 reserve0,
        uint8 token0Decimals,
        uint128 reserve1,
        uint8 token1Decimals
    )
        internal
        pure
        returns (
            uint128,
            uint128,
            uint8
        )
    {
        /// @dev Conditionally change the decimal to target := max(decimal0, decimal1)
        /// return tuple of modified reserve values in matching decimals
        if (token0Decimals > token1Decimals) {
            return (
                reserve0,
                uint128(reserve1 * 10**(token0Decimals - token1Decimals)),
                token0Decimals
            );
        } else if (token0Decimals < token1Decimals) {
            return (
                uint128(reserve0 * 10**(token1Decimals - token0Decimals)),
                reserve1,
                token1Decimals
            );
        } else {
            return (reserve0, reserve1, token0Decimals);
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
    ) internal view returns (uint256) {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        uint8 targetDecimalsQuote = _getTargetDecimals(quoteToken);
        uint8 targetDecimalsBase = _getTargetDecimals(baseToken);

        uint256 adjustedFixed128x128Quote;
        uint256 quoteAmount;

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);

            adjustedFixed128x128Quote = uint256(quoteAmount) << 128;

            if (targetDecimalsQuote < targetDecimalsBase) {
                return adjustedFixed128x128Quote / 10**targetDecimalsQuote;
            } else {
                return
                    adjustedFixed128x128Quote /
                    (10 **
                        ((targetDecimalsQuote - targetDecimalsBase) +
                            targetDecimalsQuote));
            }
        } else {
            uint256 ratioX128 = FullMath.mulDiv(
                sqrtRatioX96,
                sqrtRatioX96,
                1 << 64
            );
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);

            adjustedFixed128x128Quote = uint256(quoteAmount) << 128;
            if (targetDecimalsQuote < targetDecimalsBase) {
                return adjustedFixed128x128Quote / 10**targetDecimalsQuote;
            } else {
                return
                    adjustedFixed128x128Quote /
                    (10 **
                        ((targetDecimalsQuote - targetDecimalsBase) +
                            targetDecimalsQuote));
            }
        }
    }
}
