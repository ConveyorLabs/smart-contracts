// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/ConveyorMath.sol";
import "./OrderBook.sol";
import "../lib/libraries/ConveyorTickMath.sol";
import "../lib/libraries/Uniswap/FullMath.sol";
import "../lib/libraries/Uniswap/TickMath.sol";
import "../lib/interfaces/token/IWETH.sol";
import "../lib/libraries/ConveyorFeeMath.sol";
import "../lib/libraries/Uniswap/SqrtPriceMath.sol";
import "../lib/interfaces/uniswap-v3/IQuoter.sol";

/// @title SwapRouter
/// @author 0xKitsune, LeytonTaylor, Conveyor Labs
/// @notice Dex aggregator that executes standalong swaps, and fulfills limit orders during execution. Contains all limit order execution structures.
contract SwapRouter {
    //----------------------Structs------------------------------------//

    ///@notice Struct to store DEX details
    ///@param factoryAddress - The factory address for the DEX
    ///@param initBytecode - The bytecode sequence needed derrive pair addresses from the factory.
    ///@param isUniV2 - Boolean to distinguish if the DEX is UniV2 compatible.
    struct Dex {
        address factoryAddress;
        bytes32 initBytecode;
        bool isUniV2;
    }

    ///@notice Struct to store price information between the tokenIn/Weth and tokenOut/Weth pairings during order batching.
    ///@param aToWethReserve0 - tokenIn reserves on the tokenIn/Weth pairing.
    ///@param aToWethReserve1 - Weth reserves on the tokenIn/Weth pairing.
    ///@param wethToBReserve0 - Weth reserves on the Weth/tokenOut pairing.
    ///@param wethToBReserve1 - tokenOut reserves on the Weth/tokenOut pairing.
    ///@param price - Price of tokenIn per tokenOut based on the exchange rate of both pairs, represented as a 128x128 fixed point.
    ///@param lpAddressAToWeth - LP address of the tokenIn/Weth pairing.
    ///@param lpAddressWethToB -  LP address of the Weth/tokenOut pairing.
    struct TokenToTokenExecutionPrice {
        uint128 aToWethReserve0;
        uint128 aToWethReserve1;
        uint128 wethToBReserve0;
        uint128 wethToBReserve1;
        uint256 price;
        address lpAddressAToWeth;
        address lpAddressWethToB;
    }

    ///@notice Struct to store price information for a tokenIn/Weth pairing.
    ///@param aToWethReserve0 - tokenIn reserves on the tokenIn/Weth pairing.
    ///@param aToWethReserve1 - Weth reserves on the tokenIn/Weth pairing.
    ///@param price - Price of tokenIn per Weth, represented as a 128x128 fixed point.
    ///@param lpAddressAToWeth - LP address of the tokenIn/Weth pairing.
    struct TokenToWethExecutionPrice {
        uint128 aToWethReserve0;
        uint128 aToWethReserve1;
        uint256 price;
        address lpAddressAToWeth;
    }

    ///@notice Struct to represent the spot price and reserve values on a given LP address
    ///@param spotPrice - Spot price of the LP address represented as a 128x128 fixed point number.
    ///@param res0 - The amount of reserves for the tokenIn.
    ///@param res1 - The amount of reserves for the tokenOut.
    ///@param token0IsReserve0 - Boolean to indicate if the tokenIn corresponds to reserve 0.
    struct SpotReserve {
        uint256 spotPrice;
        uint128 res0;
        uint128 res1;
        bool token0IsReserve0;
    }

    //----------------------State Variables------------------------------------//

    uint256 uniV3AmountOut;

    //----------------------State Structures------------------------------------//

    ///@notice Array of Dex that is used to calculate spot prices for a given order.
    Dex[] public dexes;

    ///@notice Mapping from DEX factory address to the index of the DEX in the dexes array
    mapping(address => uint256) dexToIndex;

    //----------------------Modifiers------------------------------------//

    //======================Events==================================

    event UniV2SwapError(string indexed reason);
    event UniV3SwapError(string indexed reason);

    //======================Constants================================

    IQuoter constant Quoter =
        IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
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

    //======================Immutables================================

    ///@notice Threshold between UniV3 and UniV2 spot price that determines if maxBeaconReward should be used.
    uint256 constant alphaXDivergenceThreshold =
        3402823669209385000000000000000000;

    //======================Constructor================================

    /**@dev It is important to note that a univ2 compatible DEX must be initialized in the 0th index.
        The _calculateFee function relies on a uniV2 DEX to be in the 0th index.*/
    ///@param _deploymentByteCodes - Array of DEX creation init bytecodes.
    ///@param _dexFactories - Array of DEX factory addresses.
    ///@param _isUniV2 - Array of booleans indicating if the DEX is UniV2 compatible.
    constructor(
        bytes32[] memory _deploymentByteCodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2
    ) {
        ///@notice Initialize DEXs and other variables
        for (uint256 i = 0; i < _deploymentByteCodes.length; ++i) {
            dexes.push(
                Dex({
                    factoryAddress: _dexFactories[i],
                    initBytecode: _deploymentByteCodes[i],
                    isUniV2: _isUniV2[i]
                })
            );
        }
    }

    //======================Functions================================

    ///@notice Transfer ETH to a specific address and require that the call was successful.
    ///@param to - The address that should be sent Ether.
    ///@param amount - The amount of Ether that should be sent.
    function safeTransferETH(address to, uint256 amount) public {
        bool success;

        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        if (!success) {
            revert ETHTransferFailed();
        }
    }

    /// @notice Helper function to calculate the logistic mapping output on a USDC input quantity for fee % calculation
    /// @dev This calculation assumes that all values are in a 64x64 fixed point uint128 representation.
    /** @param amountIn - Amount of Weth represented as a 64x64 fixed point value to calculate the fee that will be applied 
    to the amountOut of an executed order. */
    ///@param usdc - Address of USDC
    ///@param weth - Address of Weth
    /// @return calculated_fee_64x64 -  Returns the fee percent that is applied to the amountOut realized from an executed.
    function _calculateFee(
        uint128 amountIn,
        address usdc,
        address weth
    ) internal view returns (uint128) {
        uint128 calculated_fee_64x64;

        ///@notice Initialize spot reserve structure to retrive the spot price from uni v2
        (SpotReserve memory _spRes, ) = _calculateV2SpotPrice(
            weth,
            usdc,
            dexes[0].factoryAddress,
            dexes[0].initBytecode
        );

        ///@notice Cache the spot price
        uint256 spotPrice = _spRes.spotPrice;

        ///@notice The SpotPrice is represented as a 128x128 fixed point value. To derive the amount in USDC, multiply spotPrice*amountIn and adjust to base 10
        uint256 amountInUSDCDollarValue = ConveyorMath.mul128I(
            spotPrice,
            amountIn
        ) / uint256(10**18);

        ///@notice if usdc value of trade is >= 1,000,000 set static fee of 0.001
        if (amountInUSDCDollarValue >= 1000000) {
            return MIN_FEE_64x64;
        }

        ///@notice 0.9 represented as 128.128 fixed point
        uint256 numerator = ZERO_POINT_NINE;

        ///@notice Exponent= usdAmount/750000
        uint128 exponent = uint128(
            ConveyorMath.divUI(amountInUSDCDollarValue, 75000)
        );

        ///@notice This is to prevent overflow, and order is of sufficient size to recieve 0.001 fee
        if (exponent >= 0x400000000000000000) {
            return MIN_FEE_64x64;
        }

        ///@notice denominator = (1.25 + e^(exponent))
        uint256 denominator = ConveyorMath.add128x128(
            ONE_POINT_TWO_FIVE,
            uint256(ConveyorMath.exp(exponent)) << 64
        );

        ///@notice divide numerator by denominator
        uint256 rationalFraction = ConveyorMath.div128x128(
            numerator,
            denominator
        );

        ///@notice add 0.1 buffer and divide by 100 to adjust fee to correct % value in range [0.001-0.005]
        calculated_fee_64x64 = ConveyorMath.div64x64(
            ConveyorMath.add64x64(
                uint128(rationalFraction >> 64),
                ZERO_POINT_ONE
            ),
            uint128(100 << 64)
        );

        return calculated_fee_64x64;
    }

    ///@notice Function that determines if the max beacon reward should be applied to a batch.
    /**@dev The max beacon reward is determined by the alpha x calculation in order to prevent profit derrived 
    from price manipulation. This function determines if the max beacon reward must be used.*/
    ///@param spotReserves - Holds the spot prices and reserve values for the batch.
    ///@param orders - All orders being prepared for execution within the batch.
    ///@param wethIsToken0 - Boolean that indicates if the token0 is Weth which determines how the max beacon reward is evaluated.
    ///@return maxBeaconReward - Returns the maxBeaconReward calculated for the batch if the maxBeaconReward should be applied.
    ///@dev If the maxBeaconReward should not be applied, MAX_UINT_128 is returned.
    function calculateMaxBeaconReward(
        SpotReserve[] memory spotReserves,
        OrderBook.Order[] memory orders,
        bool wethIsToken0
    ) internal view returns (uint128 maxBeaconReward) {
        ///@notice Cache the first order buy status.
        bool buy = orders[0].buy;

        ///@notice Initialize v2Outlier to the max/min depending on order status.
        uint256 v2Outlier = buy
            ? 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            : 0;

        ///@notice Initialize variables involved in conditional logic.
        uint256 v3Spot;
        bool v3PairExists;
        uint256 v2OutlierIndex;

        ///@dev Scoping to avoid stack too deep errors.
        {
            ///@notice For each spot reserve in the spotReserves array
            for (uint256 i = 0; i < spotReserves.length; ) {
                ///@notice If the dex is not uniV2 compatible
                if (!dexes[i].isUniV2) {
                    ///@notice Update the v3Spot price
                    v3Spot = spotReserves[i].spotPrice;
                    if (v3Spot == 0) {
                        v3PairExists = false;
                    } else {
                        v3PairExists = true;
                    }
                } else {
                    ///@notice if the order is a buy order
                    if (buy) {
                        ///@notice if the spotPrice is less than the v2Outlier, assign the spotPrice to the v2Outlier.
                        if (spotReserves[i].spotPrice < v2Outlier) {
                            v2OutlierIndex = i;
                            v2Outlier = spotReserves[i].spotPrice;
                        }
                    } else {
                        ///@notice if the order is a sell order and the spot price is greater than the v2Outlier, assign the spotPrice to the v2Outlier.
                        if (spotReserves[i].spotPrice > v2Outlier) {
                            v2OutlierIndex = i;
                            v2Outlier = spotReserves[i].spotPrice;
                        }
                    }
                }

                unchecked {
                    ++i;
                }
            }
        }

        ///@notice if the order is a buy order and the v2Outlier is greater than the v3Spot price
        if (buy && v2Outlier > v3Spot) {
            ///@notice return the max uint128 value as the max beacon reward.
            return MAX_UINT_128;
        } else if (!(buy) && v2Outlier < v3Spot) {
            /**@notice if the order is a sell order and the v2Outlier is less than the v3Spot price
           return the max uint128 value as the max beacon reward.*/
            return MAX_UINT_128;
        }

        ///@notice Initialize variables involved in conditional logic.
        ///@dev This is separate from the previous logic to keep the stack lean and avoid stack overflows.
        uint256 priceDivergence;

        maxBeaconReward = MAX_UINT_128;

        ///@dev Scoping to avoid stack too deep errors.
        {
            ///@notice If a v3Pair exists for the order
            if (v3PairExists) {
                ///@notice Calculate proportional difference between the v3 and v2Outlier price
                priceDivergence = ConveyorFeeMath._calculatePriceDivergence(
                    v3Spot,
                    v2Outlier
                );

                ///@notice If the difference crosses the alphaXDivergenceThreshold, then calulate the max beacon fee.
                if (priceDivergence > alphaXDivergenceThreshold) {
                    maxBeaconReward = ConveyorFeeMath._calculateMaxBeaconReward(
                            priceDivergence,
                            spotReserves[v2OutlierIndex].res0,
                            spotReserves[v2OutlierIndex].res1,
                            UNI_V2_FEE
                        );
                }
            }
        }

        ///@notice If weth is not token0, then convert the maxBeaconValue into Weth.
        if (!wethIsToken0) {
            ///@notice Convert the alphaX*fee quantity into Weth
            maxBeaconReward = uint128(
                ConveyorMath.mul128I(v2Outlier, maxBeaconReward)
            );
        }

        return maxBeaconReward;
    }

    function transferTokensOutToOwner(
        address orderOwner,
        uint256 amount,
        address tokenOut
    ) internal {
        try IERC20(tokenOut).transfer(orderOwner, amount) {} catch {
            revert TokenTransferFailed(bytes32(0));
        }
    }

    function transferBeaconReward(
        uint256 totalBeaconReward,
        address executorAddress,
        address weth
    ) internal {
        ///@notice Unwrap the total reward.
        IWETH(weth).withdraw(totalBeaconReward);

        ///@notice Send the off-chain executor their reward.
        safeTransferETH(executorAddress, totalBeaconReward);
    }

    //------------------------Admin Functions----------------------------

    ///@notice Helper function to execute a swap on a UniV2 LP
    ///@param _tokenIn - Address of the tokenIn.
    ///@param _tokenOut - Address of the tokenOut.
    ///@param _lp - Address of the lp.
    ///@param _amountIn - AmountIn for the swap.
    ///@param _amountOutMin - AmountOutMin for the swap.
    ///@param _reciever - Address to receive the amountOut.
    ///@param _sender - Address to send the tokenIn.
    ///@return amountRecieved - Amount received from the swap.
    function _swapV2(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _reciever,
        address _sender
    ) internal returns (uint256 amountRecieved) {
        ///@notice If the sender is not the current context
        ///@dev This can happen when swapping taxed tokens to avoid being double taxed by sending the tokens to the contract instead of directly to the lp
        if (_sender != address(this)) {
            ///@notice Transfer the tokens to the lp from the sender.
            IERC20(_tokenIn).transferFrom(_sender, _lp, _amountIn);
        } else {
            ///@notice Transfer the tokens to the lp from the current context.
            IERC20(_tokenIn).transfer(_lp, _amountIn);
        }

        ///@notice Get token0 from the pairing.
        (address token0, ) = ConveyorFeeMath._sortTokens(_tokenIn, _tokenOut);

        ///@notice Intialize the amountOutMin value
        (uint256 amount0Out, uint256 amount1Out) = _tokenIn == token0
            ? (uint256(0), _amountOutMin)
            : (_amountOutMin, uint256(0));

        ///@notice Get the balance before the swap to know how much was received from swapping.
        uint256 balanceBefore = IERC20(_tokenOut).balanceOf(_reciever);

        ///@notice Execute the swap on the lp for the amounts specified.
        IUniswapV2Pair(_lp).swap(
            amount0Out,
            amount1Out,
            _reciever,
            new bytes(0)
        );

        ///@notice calculate the amount recieved
        amountRecieved = IERC20(_tokenOut).balanceOf(_reciever) - balanceBefore;

        ///@notice if the amount recieved is less than the amount out min, revert
        if (amountRecieved < _amountOutMin) {
            revert InsufficientOutputAmount();
        }

        return amountRecieved;
    }

    receive() external payable {}

    ///@notice Agnostic swap function that determines whether or not to swap on univ2 or univ3
    ///@param _tokenIn - Address of the tokenIn.
    ///@param _tokenOut - Address of the tokenOut.
    ///@param _lp - Address of the lp.
    ///@param _fee - Fee for the lp address.
    ///@param _amountIn - AmountIn for the swap.
    ///@param _amountOutMin - AmountOutMin for the swap.
    ///@param _reciever - Address to receive the amountOut.
    ///@param _sender - Address to send the tokenIn.
    ///@return amountRecieved - Amount received from the swap.
    function swap(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _reciever,
        address _sender
    ) internal returns (uint256 amountRecieved) {
        if (_lpIsNotUniV3(_lp)) {
            amountRecieved = _swapV2(
                _tokenIn,
                _tokenOut,
                _lp,
                _amountIn,
                _amountOutMin,
                _reciever,
                _sender
            );
        } else {
            amountRecieved = _swapV3(
                _lp,
                _tokenIn,
                _fee,
                _amountIn,
                _amountOutMin,
                _reciever,
                _sender
            );
        }
    }

    ///@notice Function to swap two tokens on a Uniswap V3 pool.
    ///@param _lp - Address of the liquidity pool to execute the swap on.
    ///@param _tokenIn - Address of the TokenIn on the swap.
    ///@param _fee - The swap fee on the liquiditiy pool.
    ///@param _amountIn The amount in for the swap.
    ///@param _amountOutMin The minimum amount out in TokenOut post swap.
    ///@param _reciever The receiver of the tokens post swap.
    ///@param _sender The sender of TokenIn on the swap.
    ///@return amountRecieved The amount of TokenOut received post swap.
    function _swapV3(
        address _lp,
        address _tokenIn,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _reciever,
        address _sender
    ) internal returns (uint256 amountRecieved) {
        ///@notice Initialize variables to prevent stack too deep.
        uint160 _sqrtPriceLimitX96;
        bool _zeroForOne;

        ///@notice Scope out logic to prevent stack too deep.
        {
            ///@notice Get the sqrtPriceLimitX96 and zeroForOne on the swap.
            (_sqrtPriceLimitX96, _zeroForOne) = getNextSqrtPriceV3(
                _lp,
                _amountIn,
                _tokenIn,
                _fee
            );
        }

        ///@notice Pack the relevant data to be retrieved in the swap callback.
        bytes memory data = abi.encode(
            _amountOutMin,
            _zeroForOne,
            _lp,
            _tokenIn,
            _sender
        );

        ///@notice Initialize Storage variable uniV3AmountOut to 0 prior to the swap.
        uniV3AmountOut = 0;

        ///@notice Execute the swap on the lp for the amounts specified.
        IUniswapV3Pool(_lp).swap(
            _reciever,
            _zeroForOne,
            int256(_amountIn),
            _sqrtPriceLimitX96,
            data
        );

        ///@notice Return the amountOut yielded from the swap.
        return uniV3AmountOut;
    }

    ///@notice Function to calculate the nextSqrtPriceX96 for a Uniswap V3 swap.
    ///@param _lp - Address of the liquidity pool to execute the swap on.
    ///@param _alphaX - The input amount to calculate the nextSqrtPriceX96.
    ///@param _tokenIn - The address of TokenIn.
    ///@param _fee - The swap fee on the liquiditiy pool.
    ///@return _sqrtPriceLimitX96 - The nextSqrtPriceX96 after alphaX amount of TokenIn is introduced to the pool.
    ///@return  _zeroForOne - Boolean indicating whether Token0 is being swapped for Token1 on the liquidity pool.
    function getNextSqrtPriceV3(
        address _lp,
        uint256 _alphaX,
        address _tokenIn,
        uint24 _fee
    ) internal returns (uint160 _sqrtPriceLimitX96, bool _zeroForOne) {
        ///@notice Initialize token0 & token1 to prevent stack too deep.
        address token0;
        address token1;
        ///@notice Scope out logic to prevent stack too deep.
        {
            ///@notice Retrieve token0 & token1 from the liquidity pool.
            token0 = IUniswapV3Pool(_lp).token0();
            token1 = IUniswapV3Pool(_lp).token1();

            ///@notice Set boolean _zeroForOne.
            _zeroForOne = token0 == _tokenIn ? true : false;
        }

        ///@notice Get the current sqrtPriceX96 from the liquidity pool.
        (uint160 _srtPriceX96, , , , , , ) = IUniswapV3Pool(_lp).slot0();

        ///@notice Get the liquditity from the liquidity pool.
        uint128 liquidity = IUniswapV3Pool(_lp).liquidity();

        ///@notice If swapping token1 for token0.

        ///@notice Get the nextSqrtPrice after introducing alphaX into the token1 reserves.
        _sqrtPriceLimitX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
            _srtPriceX96,
            liquidity,
            _alphaX,
            _zeroForOne
        );
    }

    ///@notice Uniswap V3 callback function called during a swap on a v3 liqudity pool.
    ///@param amount0Delta - The change in token0 reserves from the swap.
    ///@param amount1Delta - The change in token1 reserves from the swap.
    ///@param data - The data packed into the swap.
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory data
    ) external {
        ///@notice Decode all of the swap data.
        (
            uint256 amountOutMin,
            bool _zeroForOne,
            address _lp,
            address tokenIn,
            address _sender
        ) = abi.decode(data, (uint256, bool, address, address, address));
        ///@notice If swapping token0 for token1.
        if (_zeroForOne) {
            ///@notice Set contract storage variable to the amountOut from the swap.
            uniV3AmountOut = uint256(-amount1Delta);

            ///@notice If swapping token1 for token0.
        } else {
            ///@notice Set contract storage variable to the amountOut from the swap.
            uniV3AmountOut = uint256(-amount0Delta);
        }

        ///@notice Require the amountOut from the swap is greater than or equal to the amountOutMin.
        if (uniV3AmountOut < amountOutMin) {
            revert InsufficientOutputAmount();
        }

        ///@notice Set amountIn to the amountInDelta depending on boolean zeroForOne.
        uint256 amountIn = _zeroForOne
            ? uint256(amount0Delta)
            : uint256(amount1Delta);

        if (!(_sender == address(this))) {
            ///@notice Transfer the amountIn of tokenIn to the liquidity pool from the sender.
            IERC20(tokenIn).transferFrom(_sender, _lp, amountIn);
        } else {
            IERC20(tokenIn).transfer(_lp, amountIn);
        }
    }

    /// @notice Helper function to get Uniswap V2 spot price of pair token0/token1.
    /// @param token0 - Address of token1.
    /// @param token1 - Address of token2.
    /// @param _factory - Factory address.
    /// @param _initBytecode - Initialization bytecode of the v2 factory contract.
    function _calculateV2SpotPrice(
        address token0,
        address token1,
        address _factory,
        bytes32 _initBytecode
    ) internal view returns (SpotReserve memory spRes, address poolAddress) {
        ///@notice Require token address's are not identical
        require(token0 != token1, "Invalid Token Pair, IDENTICAL Address's");

        address tok0;
        address tok1;

        {
            (tok0, tok1) = ConveyorFeeMath._sortTokens(token0, token1);
        }

        ///@notice SpotReserve struct to hold the reserve values and spot price of the dex.
        SpotReserve memory _spRes;

        ///@notice Get pool address on the token pair.
        address pairAddress = ConveyorFeeMath._getV2PairAddress(
            _factory,
            tok0,
            tok1,
            _initBytecode
        );

        require(pairAddress != address(0), "Invalid token pair");

        ///@notice If the token pair does not exist on the dex return empty SpotReserve struct.
        if (!(IUniswapV2Factory(_factory).getPair(tok0, tok1) == pairAddress)) {
            return (_spRes, address(0));
        }
        {
            ///@notice Set reserve0, reserve1 to current LP reserves
            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pairAddress)
                .getReserves();

            ///@notice Convert the reserve values to a common decimal base.
            (
                uint256 commonReserve0,
                uint256 commonReserve1
            ) = _getReservesCommonDecimals(tok0, tok1, reserve0, reserve1);

            ///@notice If tokenIn is token0 on the pair address.
            ///@notice Always set the tokenIn to _spRes.res0 in the SpotReserve structure
            if (token0 == tok0) {
                ///@notice Set spotPrice to the current spot price on the dex represented as 128.128 fixed point.
                _spRes.spotPrice = ConveyorMath.div128x128(
                    commonReserve1 << 128,
                    commonReserve0 << 128
                );
                _spRes.token0IsReserve0 = true;

                ///@notice Set res0, res1 on SpotReserve to commonReserve0, commonReserve1 respectively.
                (_spRes.res0, _spRes.res1) = (
                    uint128(commonReserve0),
                    uint128(commonReserve1)
                );
            } else {
                ///@notice Set spotPrice to the current spot price on the dex represented as 128.128 fixed point.
                _spRes.spotPrice = ConveyorMath.div128x128(
                    commonReserve0 << 128,
                    commonReserve1 << 128
                );
                _spRes.token0IsReserve0 = false;

                ///@notice Set spotPrice to the current spot price on the dex represented as 128.128 fixed point.
                (_spRes.res1, _spRes.res0) = (
                    uint128(commonReserve0),
                    uint128(commonReserve1)
                );
            }
        }

        ///@notice Return pool address and populated SpotReserve struct.
        (spRes, poolAddress) = (_spRes, pairAddress);
    }

    ///@notice Helper function to convert reserve values to common 18 decimal base.
    ///@param tok0 - Address of token0.
    ///@param tok1 - Address of token1.
    ///@param reserve0 - Reserve0 liquidity.
    ///@param reserve1 - Reserve1 liquidity.
    function _getReservesCommonDecimals(
        address tok0,
        address tok1,
        uint128 reserve0,
        uint128 reserve1
    ) internal view returns (uint128, uint128) {
        ///@notice Get target decimals for token0 & token1
        uint8 token0Decimals = IERC20(tok0).decimals();
        uint8 token1Decimals = IERC20(tok1).decimals();

        ///@notice Retrieve the common 18 decimal reserve values.
        uint128 commonReserve0 = token0Decimals <= 18
            ? uint128(reserve0 * (10**(18 - token0Decimals)))
            : uint128(reserve0 * (10**(token0Decimals - 18)));
        uint128 commonReserve1 = token1Decimals <= 18
            ? uint128(reserve1 * (10**(18 - token1Decimals)))
            : uint128(reserve1 * (10**(token1Decimals - 18)));
        return (commonReserve0, commonReserve1);
    }

    /// @notice Helper function to get Uniswap V3 spot price of pair token0/token1
    /// @param token0 - Address of token0.
    /// @param token1 - Address of token1.
    /// @param fee - The fee in the pool.
    /// @param _factory - Uniswap v3 factory address.
    /// @return  _spRes SpotReserve struct to hold reserve0, reserve1, and the spot price of the token pair.
    /// @return pool Address of the Uniswap V3 pool.
    function _calculateV3SpotPrice(
        address token0,
        address token1,
        uint24 fee,
        address _factory
    ) internal view returns (SpotReserve memory _spRes, address pool) {
        ///@notice Initialize variables to prevent stack too deep.
        int24 tick;

        uint32 tickSecond = 1; //Instantaneous price to use as baseline for maxBeaconReward analysis
        uint8 targetDecimals = IERC20(token0).decimals() >=
            IERC20(token1).decimals()
            ? IERC20(token0).decimals()
            : IERC20(token1).decimals();
        ///@notice Set amountIn to the amountIn value in the the max token decimals of token0/token1.
        uint112 amountIn = uint112(10**targetDecimals);

        ///@notice Scope to prevent stack too deep error.
        {
            ///@notice Get the pool address for token pair.
            pool = IUniswapV3Factory(_factory).getPool(token0, token1, fee);

            ///@notice If the pool does not exist on the dex, return empty SpotReserve structure and address(0).
            if (pool == address(0)) {
                return (_spRes, address(0));
            }

            ///@notice Notice current tick on the pool.
            {
                tick = _getTick(pool, tickSecond);
            }
        }

        ///@notice Set token0InPool to token0 in pool.
        address token0InPool = IUniswapV3Pool(pool).token0();

        _spRes.token0IsReserve0 = token0InPool == token0 ? true : false;

        ///@notice Get the current spot price of the pool.
        _spRes.spotPrice = _getQuoteAtTick(tick, amountIn, token0, token1);

        return (_spRes, pool);
    }

    ///@notice Helper function to determine if a pool address is Uni V2 compatible.
    ///@param lp - Pair address.
    ///@return bool Idicator whether the pool is not Uni V3 compatible.
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
        ///@notice indicate that lpIsNotUniV3 is false
        return !success;
    }

    ///@notice Helper function to get arithmetic mean tick from Uniswap V3 Pool.
    ///@param pool - Address of the pool.
    ///@param tickSecond - The tick range.
    ///@return tick Arithmetic mean tick over the range tickSeconds.
    function _getTick(address pool, uint32 tickSecond)
        internal
        view
        returns (int24 tick)
    {
        int56 tickCumulativesDelta;

        ///@notice Initialize tickSeconds range.
        uint32[] memory tickSeconds = new uint32[](2);
        tickSeconds[0] = tickSecond;
        tickSeconds[1] = 0;

        {
            ///@notice Retrieve tickCumulatives from the observation over the pool from tickSeconds[1]-> tickSeconds[0]
            (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(
                tickSeconds
            );

            ///@notice Set tickCumulativesDelta to the difference in spot prices from tickCumulatives[1] to the current block.
            tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
            tick = int24(tickCumulativesDelta / int32(tickSecond));

            if (
                tickCumulativesDelta < 0 &&
                (tickCumulativesDelta % int32(tickSecond) != 0)
            ) tick--;
        }

        return tick;
    }

    /// @notice Helper function to get all v2/v3 spot prices on a token pair.
    /// @param token0 - Address of token0.
    /// @param token1 - Address of token1.
    /// @param FEE - The Uniswap V3 pool fee on the token pair.
    /// @return prices - SpotReserve array holding the reserves and spot prices across all dexes.
    /// @return lps - Pool address's on the token pair across all dexes.
    function _getAllPrices(
        address token0,
        address token1,
        uint24 FEE
    )
        internal
        view
        returns (SpotReserve[] memory prices, address[] memory lps)
    {
        ///@notice Check if the token address' are identical.
        if (token0 != token1) {
            ///@notice Initialize SpotReserve and lp arrays of lenth dexes.length
            SpotReserve[] memory _spotPrices = new SpotReserve[](dexes.length);
            address[] memory _lps = new address[](dexes.length);

            ///@notice Iterate through Dexs in dexes and check if isUniV2.
            for (uint256 i = 0; i < dexes.length; ++i) {
                if (dexes[i].isUniV2) {
                    {
                        ///@notice Get the Uniswap v2 spot price and lp address.
                        (
                            SpotReserve memory spotPrice,
                            address poolAddress
                        ) = _calculateV2SpotPrice(
                                token0,
                                token1,
                                dexes[i].factoryAddress,
                                dexes[i].initBytecode
                            );
                        ///@notice Set SpotReserve and lp values if the returned values are not null.
                        if (spotPrice.spotPrice != 0) {
                            _spotPrices[i] = spotPrice;
                            _lps[i] = poolAddress;
                        }
                    }
                } else {
                    {
                        {
                            ///@notice Get the Uniswap v2 spot price and lp address.
                            (
                                SpotReserve memory spotPrice,
                                address poolAddress
                            ) = _calculateV3SpotPrice(
                                    token0,
                                    token1,
                                    FEE,
                                    dexes[i].factoryAddress
                                );

                            ///@notice Set SpotReserve and lp values if the returned values are not null.
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

    /// @notice Helper function to calculate the the quote amount recieved for the base amount of the base token at a certain tick.
    /// @param tick - Tick value used to calculate the quote.
    /// @param baseAmount - Amount of tokenIn to be converted.
    /// @param baseToken - Address of the tokenIn to be quoted.
    /// @param quoteToken - Address of the token used to quote the base amount of tokenIn.
    /// @return quoteAmount - Amount of quoteToken received for baseAmount of baseToken.
    function _getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal view returns (uint256) {
        ///@notice Get sqrtRatio at tick represented as 64.96 fixed point.
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        ///@notice Get the target decimals of the quote and base token.
        uint8 targetDecimalsQuote = IERC20(quoteToken).decimals();
        uint8 targetDecimalsBase = IERC20(baseToken).decimals();

        ///@notice Initialize Adjusted quote amount to hold the quote amount represented as a 128.128 fixed point number.
        uint256 adjustedFixed128x128Quote;
        uint256 quoteAmount;

        ///@notice Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself.
        if (sqrtRatioX96 <= type(uint128).max) {
            ///@notice Square the sqrt price to get the 64.96 representation of the spot price.
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
