// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../lib/interfaces/token/IERC20.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/ConveyorMath.sol";
import "../lib/libraries/ConveyorTickMath.sol";
import "./OrderBook.sol";
import "../lib/libraries/Uniswap/FullMath.sol";
import "../lib/libraries/Uniswap/TickMath.sol";
import "../lib/interfaces/uniswap-v3/ISwapRouter.sol";
import "../lib/interfaces/token/IWETH.sol";
import "../lib/libraries/Uniswap/LowGasSafeMath.sol";
import "../lib/libraries/QuadruplePrecision.sol";

/// @title OrderRouter
/// @author 0xKitsune, LeytonTaylor
/// @notice TODO:
contract OrderRouter {
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

    ///@notice Struct to represent a batch order from tokenIn/Weth
    ///@dev A batch order takes many elligible orders and combines the amountIn to execute one swap instead of many.
    ///@param batchLength - Amount of orders that were combined into the batch.
    ///@param amountIn - The aggregated amountIn quantity from all orders in the batch.
    ///@param amountOutMin - The aggregated amountOut quantity from all orders in the batch.
    ///@param tokenIn - The tokenIn for the batch order.
    ///@param lpAddress - The LP address that the batch order will be executed on.
    ///@param batchOwners - Array of account addresses representing the owners of the orders that were aggregated into the batch.
    ///@param ownerShares - Array of values representing the individual order's amountIn. Each index corresponds to the owner at index in orderOwners.
    ///@param orderIds - Array of values representing the individual order's orderIds. Each index corresponds to the owner at index in orderOwners.
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

    ///@notice Struct to represent a batch order from tokenIn/tokenOut
    ///@dev A batch order takes many elligible orders and combines the amountIn to execute one swap instead of many.
    ///@param batchLength - Amount of orders that were combined into the batch.
    ///@param amountIn - The aggregated amountIn quantity from all orders in the batch.
    ///@param amountOutMin - The aggregated amountOut quantity from all orders in the batch.
    ///@param tokenIn - The tokenIn for the batch order.
    ///@param tokenIn - The tokenOut for the batch order.
    ///@param lpAddressAToWeth - The LP address that the first hop of the batch order will be executed on.
    ///@param lpAddressWethToB - The LP address that the second hop of the batch order will be executed on.
    ///@param batchOwners - Array of account addresses representing the owners of the orders that were aggregated into the batch.
    ///@param ownerShares - Array of values representing the individual order's amountIn. Each index corresponds to the owner at index in orderOwners.
    ///@param orderIds - Array of values representing the individual order's orderIds. Each index corresponds to the owner at index in orderOwners.
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

    ///@notice The owner of the Order Router contract
    ///@dev TODO: say what the owner can do
    address owner;

    //----------------------State Structures------------------------------------//

    ///@notice Array of Dex that is used to calculate spot prices for a given order.
    Dex[] public dexes;

    ///@notice Mapping from DEX factory address to the index of the DEX in the dexes array
    mapping(address => uint256) dexToIndex;

    //----------------------Modifiers------------------------------------//

    ///@notice Modifier function to only allow the owner of the contract to call specific functions
    ///@dev TODO: list functions with only owner modifier
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert MsgSenderIsNotOwner();
        }

        _;
    }

    //======================Constants==================================
    uint128 constant MIN_FEE_64x64 = 18446744073709552;
    uint128 constant MAX_UINT_128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint128 constant UNI_V2_FEE = 5534023222112865000;

    //----------------------Immutables------------------------------------//

    ///@notice Variable used to prevent front running by subsidizing the execution reward if a v2 price is proportionally beyond the threshold distance from the v3 price

    ///@notice Threshold between UniV3 and UniV2 spot price that determines if maxBeaconReward should be used.
    uint256 immutable alphaXDivergenceThreshold;

    ///@notice Instance of the UniV3 swap router.
    ISwapRouter public immutable swapRouter;

    //----------------------Constructor------------------------------------//

    /**@dev It is important to note that a univ2 compatible DEX must be initialized in the 0th index.
     The _calculateFee function relies on a uniV2 DEX to be in the 0th index.*/
    ///@param _deploymentByteCodes - Array of DEX creation init bytecodes.
    ///@param _dexFactories - Array of DEX factory addresses.
    ///@param _isUniV2 - Array of booleans indicating if the DEX is UniV2 compatible.
    ///@param _swapRouterAddress - The UniV3 swap router address for the network.
    ///@param _alphaXDivergenceThreshold - Threshold between UniV3 and UniV2 spot price that determines if maxBeaconReward should be used.
    constructor(
        bytes32[] memory _deploymentByteCodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2,
        address _swapRouterAddress,
        uint256 _alphaXDivergenceThreshold
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
        alphaXDivergenceThreshold = _alphaXDivergenceThreshold;
        swapRouter = ISwapRouter(_swapRouterAddress);
        owner = msg.sender;
    }

    //----------------------Functions------------------------------------//

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

    //TODO: FIXME: update all constant values to constant variables
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
        uint256 numerator = 16602069666338597000 << 64;

        ///@notice Exponent= usdAmount/750000
        uint128 exponent = uint128(
            ConveyorMath.divUI(amountInUSDCDollarValue, 75000)
        );

        ///@notice This is to prevent overflow, and order is of sufficient size to recieve 0.001 fee
        if (exponent >= 0x400000000000000000) {
            return MIN_FEE_64x64;
        }

        ///@notice denominator = (2.5 + e^(exponent))
        uint256 denominator = ConveyorMath.add128x128(
            23058430092136940000 << 64,
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
                1844674407370955300
            ),
            uint128(100 << 64)
        );

        return calculated_fee_64x64;
    }

    /// @notice Helper function to calculate beacon and conveyor reward on transaction execution.
    /// @param percentFee - Percentage of order size to be taken from user order size.
    /// @param wethValue - Total order value at execution price, represented in wei.
    /// @return conveyorReward - Conveyor reward, represented in wei.
    /// @return beaconReward - Beacon reward, represented in wei.

    //TODO: FIXME: update all constant values to constant variables

    function _calculateReward(uint128 percentFee, uint128 wethValue)
        internal
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
        if (percentFee <= 92233720368547760) {
            int256 innerPartial = int256(92233720368547760) -
                int128(percentFee);

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

        ///@notice Multiply conveyorPercent by total reward to retrive conveyorReward
        conveyorReward = uint128(
            ConveyorMath.mul64I(conveyorPercent, totalWethReward)
        );

        beaconReward = uint128(totalWethReward) - conveyorReward;

        return (conveyorReward, beaconReward);
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
    ) internal returns (uint128 maxBeaconReward) {
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
        uint256 snapShotSpot;
        maxBeaconReward = MAX_UINT_128;

        ///@dev Scoping to avoid stack too deep errors.
        {
            ///@notice If a v3Pair exists for the order
            if (v3PairExists) {
                ///@notice Calculate proportional difference between the v3 and v2Outlier price
                priceDivergence = _calculatePriceDivergence(v3Spot, v2Outlier);

                ///@notice If the difference crosses the alphaXDivergenceThreshold, then calulate the max beacon fee.
                if (priceDivergence > alphaXDivergenceThreshold) {
                    maxBeaconReward = _calculateMaxBeaconReward(
                        priceDivergence,
                        spotReserves[v2OutlierIndex].res0,
                        spotReserves[v2OutlierIndex].res1,
                        UNI_V2_FEE
                    );
                }
            } else {
                ///@notice If v3 pair does not exist then calculate the alphaXDivergenceThreshold
                ///@dev The alphaXDivergenceThreshold is calculated from the price that is the maximum distance from the v2Outlier.
                (
                    priceDivergence,
                    snapShotSpot
                ) = _calculatePriceDivergenceFromBatchMin(
                    v2Outlier,
                    orders,
                    buy
                );

                ///@notice If the difference crosses the alphaXDivergenceThreshold, then calulate the max beacon fee.
                if (priceDivergence > alphaXDivergenceThreshold) {
                    maxBeaconReward = _calculateMaxBeaconReward(
                        snapShotSpot,
                        spotReserves[v2OutlierIndex].res0,
                        spotReserves[v2OutlierIndex].res1,
                        UNI_V2_FEE
                    );
                }
            }
        }

        ///@notice If weth is not token0, then convert the maxBeaconValue into Weth.
        if (!wethIsToken0) {
            ///Convert the alphaX*fee quantity into the out token i.e weth
            maxBeaconReward = uint128(
                ConveyorMath.mul128I(v2Outlier, maxBeaconReward)
            );
        }

        return maxBeaconReward;
    }

    ///@notice Helper function to calculate the proportional difference between the *minimum* priced order in the batch relative to the buy sell status of the batch
    ///@param v2Outlier spotPrice of the v2Outlier used to cross reference agains alphaXDivergenceThreshold
    ///@param orders array of order's to compare the spot price against
    ///@param buy boolean indicating buy/sell status of the batch
    function _calculatePriceDivergenceFromBatchMin(
        uint256 v2Outlier,
        OrderBook.Order[] memory orders,
        bool buy
    ) internal pure returns (uint256, uint256) {
        uint256 targetSpot = buy
            ? 0
            : 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        for (uint256 i = 0; i < orders.length; ++i) {
            uint256 orderPrice = orders[i].price;
            if (buy) {
                if (orderPrice > targetSpot) {
                    targetSpot = orderPrice;
                }
            } else {
                if (orderPrice < targetSpot) {
                    targetSpot = orderPrice;
                }
            }
        }

        uint256 proportionalSpotChange;
        uint256 priceDivergence;

        if (targetSpot > v2Outlier) {
            proportionalSpotChange = ConveyorMath.div128x128(
                v2Outlier,
                targetSpot
            );
            priceDivergence = (uint256(1) << 128) - proportionalSpotChange;
        } else {
            proportionalSpotChange = ConveyorMath.div128x128(
                targetSpot,
                v2Outlier
            );
            priceDivergence = (uint256(1) << 128) - proportionalSpotChange;
        }

        return (priceDivergence, targetSpot);
    }

    ///@notice Helper function to determine the proportional difference between two spot prices
    function _calculatePriceDivergence(uint256 v3Spot, uint256 v2Outlier)
        internal
        returns (uint256)
    {
        uint256 proportionalSpotChange;
        uint256 priceDivergence;
        if (v3Spot > v2Outlier) {
            proportionalSpotChange = ConveyorMath.div128x128(v2Outlier, v3Spot);

            priceDivergence = (uint256(1) << 128) - proportionalSpotChange;
        } else if (v3Spot == v2Outlier) {
            return 0;
        } else {
            proportionalSpotChange = ConveyorMath.div128x128(v3Spot, v2Outlier);

            priceDivergence = (uint256(1) << 128) - proportionalSpotChange;
        }

        return priceDivergence;
    }

    /// @notice Helper function to calculate the max beacon reward for a group of order's
    /// @param reserve0 uint256 reserve0 of lp at execution time
    /// @param reserve1 uint256 reserve1 of lp at execution time
    /// @param fee uint256 lp fee
    /// @return maxReward uint256 maximum safe beacon reward to protect against flash loan price manipulation in the lp
    function _calculateMaxBeaconReward(
        uint256 delta,
        uint128 reserve0,
        uint128 reserve1,
        uint128 fee
    ) public view returns (uint128) {
        uint128 maxReward = uint128(
            ConveyorMath.mul64I(
                fee,
                _calculateAlphaX(delta, reserve0, reserve1)
            )
        );

        return maxReward;
    }

    /// @notice Helper function to calculate the input amount needed to manipulate the spot price of the pool from snapShot to executionPrice
    /// @param reserve0Execution snapShot of reserve0 at snapShot time
    /// @param reserve1Execution snapShot of reserve1 at snapShot time
    /// @return alphaX alphaX amount to manipulate the spot price of the respective lp to execution trigger
    function _calculateAlphaX(
        uint256 delta,
        uint128 reserve0Execution,
        uint128 reserve1Execution
    ) internal view returns (uint256) {
        //k = r'x*r'y
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
        if (sender != address(this)) {
            /// transfer the tokens to the lp
            IERC20(_tokenIn).transferFrom(sender, _lp, _amountIn);
        } else {
            IERC20(_tokenIn).transfer(_lp, _amountIn);
        }

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
        {} catch {
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

            return _amountOut;
        } catch {
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
                uint256 commonReserve1
            ) = _getReservesCommonDecimals(tok0, tok1, reserve0, reserve1);

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
        address tok0,
        address tok1,
        uint128 reserve0,
        uint128 reserve1
    ) internal view returns (uint128, uint128) {
        //Get target decimals for token0 & token1
        uint8 token0Decimals = _getTargetDecimals(tok0);
        uint8 token1Decimals = _getTargetDecimals(tok1);

        //Set common based reserve values
        (uint128 commonReserve0, uint128 commonReserve1) = _convertToCommonBase(
            reserve0,
            token0Decimals,
            reserve1,
            token1Decimals
        );

        return (commonReserve0, commonReserve1);
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
            bool token0IsReserve0
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
                uint128 commonReserve1
            ) = _convertToCommonBase(
                    reserve0,
                    token0Decimals,
                    reserve1,
                    token1Decimals
                );

            return (commonReserve0, commonReserve1, token0IsReserve0);
        } else {
            //Set common based reserve values
            (
                uint128 commonReserve0,
                uint128 commonReserve1
            ) = _convertToCommonBase(
                    reserve0,
                    token1Decimals,
                    reserve1,
                    token0Decimals
                );

            return (commonReserve1, commonReserve0, token0IsReserve0);
        }
    }

    // function _getV3PairAddress(address token0, address token1)
    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @param fee lp fee
    /// @param _factory Uniswap v3 factory address
    function _calculateV3SpotPrice(
        address token0,
        address token1,
        uint24 fee,
        address _factory
    ) internal returns (SpotReserve memory, address) {
        SpotReserve memory _spRes;

        address pool;
        int24 tick;
        ///FIXME: change this to 600
        uint32 tickSecond = 1; //10 minute time weighted average price to use as baseline for maxBeaconReward analysis
        ///FIXME: don't forget this is important
        uint112 amountIn = _getGreatestTokenDecimalsAmountIn(token0, token1);
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
                _spRes.token0IsReserve0
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
    /// @param FEE uniV3 fee
    function _getAllPrices(
        address token0,
        address token1,
        uint24 FEE
    ) internal returns (SpotReserve[] memory prices, address[] memory lps) {
        if (token0 != token1) {
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
                                    FEE,
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
    ) internal pure returns (uint128, uint128) {
        uint128 reserve0Common18 = token0Decimals <= 18
            ? uint128(reserve0 * 10**(18 - token0Decimals))
            : uint128(reserve0 / (10**(token0Decimals - 18)));
        uint128 reserve1Common18 = token1Decimals <= 18
            ? uint128(reserve1 * 10**(18 - token1Decimals))
            : uint128(reserve1 / (10**(token1Decimals - 18)));
        return (reserve0Common18, reserve1Common18);
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
