// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/ConveyorMath.sol";
import "../lib/libraries/Uniswap/SqrtPriceMath.sol";
import "./OrderBook.sol";
import "./OrderRouter.sol";
import "./ConveyorErrors.sol";
import "../lib/libraries/Uniswap/FullMath.sol";
import "../lib/interfaces/token/IWETH.sol";
import "../lib/interfaces/uniswap-v3/IQuoter.sol";
import "../lib/libraries/ConveyorTickMath.sol";

/// @title OrderRouter
/// @author LeytonTaylor, 0xKitsune, Conveyor Labs
/// @notice Limit Order contract to execute existing limit orders within the OrderBook contract.
contract TokenToWethExecution is OrderRouter {
    // ========================================= Modifiers =============================================

    ///@notice Conveyor funds balance in the contract.
    uint256 conveyorBalance;

    // ========================================= Constants  =============================================

    ///@notice The wrapped native token address for the chain.
    address immutable WETH;

    ///@notice The USD pegged token address for the chain.
    address immutable USDC;

    ///@notice IQuoter instance to quote the amountOut for a given amountIn on a UniV3 pool.
    IQuoter immutable iQuoter;

    ///@notice State variable to track the amount of gas initally alloted during executeOrders.
    uint256 initialTxGas;

    // ========================================= Constructor =============================================

    ///@param _weth - Address of the wrapped native token for the chain.
    ///@param _usdc - Address of the USD pegged token for the chain.
    ///@param _quoterAddress - Address for the IQuoter instance.
    ///@param _initByteCodes - Array of initBytecodes required to calculate pair addresses for each DEX.
    ///@param _dexFactories - Array of DEX factory addresses to be added to the system.
    ///@param _isUniV2 - Array indicating if a DEX factory passed in during initialization is a UniV2 compatiable DEX.
    ///@param _swapRouter - Address of the UniV3 SwapRouter for the chain.
    ///@param _alphaXDivergenceThreshold - Threshold between UniV3 and UniV2 spot price that determines if maxBeaconReward should be used.
    constructor(
        address _weth,
        address _usdc,
        address _quoterAddress,
        bytes32[] memory _initByteCodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2,
        address _swapRouter,
        uint256 _alphaXDivergenceThreshold
    )
        OrderRouter(
            _initByteCodes,
            _dexFactories,
            _isUniV2,
            _swapRouter,
            _alphaXDivergenceThreshold
        )
    {
        iQuoter = IQuoter(_quoterAddress);
        WETH = _weth;
        USDC = _usdc;
    }

    // ========================================= FUNCTIONS =============================================

    // ==================== Order Execution Functions =========================

    ///@notice Function to execute a batch of Token to Weth Orders.
    function executeTokenToWethOrders(OrderBook.Order[] memory orders)
        external
    {
        ///@notice Get all of the execution prices on TokenIn to Weth for each dex.
        (
            TokenToWethExecutionPrice[] memory executionPrices,
            uint128 maxBeaconReward
        ) = _initializeTokenToWethExecutionPrices(orders);

        ///@notice Get the batch of order's targeted on the best priced Lp's
        TokenToWethBatchOrder[]
            memory tokenToWethBatchOrders = _batchTokenToWethOrders(
                orders,
                executionPrices
            );

        ///@notice Pass the batches into the internal execution function to execute each individual batch.
        _executeTokenToWethBatchOrders(tokenToWethBatchOrders, maxBeaconReward);
    }

    ///@notice Function to execute a batch of Token to Weth Orders.
    function executeTokenToWethOrderSingle(OrderBook.Order[] memory orders)
        external
    {
        ///@notice Get all of the execution prices on TokenIn to Weth for each dex.
        (
            TokenToWethExecutionPrice[] memory executionPrices,
            uint128 maxBeaconReward
        ) = _initializeTokenToWethExecutionPrices(orders);

        ///@notice Create a variable to track the best execution price in the array of execution prices.
        uint256 bestPriceIndex = _findBestTokenToWethExecutionPrice(
            executionPrices,
            orders[0].buy
        );

        ///@notice Pass the order, maxBeaconReward, and TokenToWethExecutionPrice into _executeTokenToWethSingle for execution.
        _executeTokenToWethSingle(
            orders[0],
            maxBeaconReward,
            executionPrices[bestPriceIndex]
        );
    }

    ///@notice Function to execute a single TokenToWeth order.
    ///@param order - The order to be executed.
    ///@param maxBeaconReward - The maximum beacon reward.
    ///@param executionPrice - The best priced TokenToWethExecutionPrice to execute the order.
    function _executeTokenToWethSingle(
        OrderBook.Order memory order,
        uint128 maxBeaconReward,
        TokenToWethExecutionPrice memory executionPrice
    ) internal {
        ///@notice Cache the order owner into memory.
        address owner = order.owner;

        ///@notice Execute the TokenIn to Weth order.
        (uint256 amountOut, uint256 beaconReward) = _executeTokenToWethOrder(
            order,
            executionPrice
        );

        ///@notice Transfer the out amount to the order owner.
        IERC20(WETH).transfer(owner, amountOut);

        /**@notice If the maxBeaconReward is greater than the beaconReward then keep the beaconReward else set beaconReward
        to the maxBeaconReward
        */
        beaconReward = maxBeaconReward > beaconReward
            ? beaconReward
            : maxBeaconReward;

        ///@notice Unwrap the beacon reward to transfer to the off-chain executor.
        IWETH(WETH).withdraw(beaconReward);
        ///@notice Send the Total Reward to the beacon.
        safeTransferETH(msg.sender, beaconReward);
    }

    ///@notice Function to return the index of the best price in the executionPrices array.
    ///@param executionPrices - Array of execution prices to evaluate.
    ///@param buyOrder - Boolean indicating whether the order is a buy or sell.
    ///@return bestPriceIndex - Index of the best price in the executionPrices array.
    function _findBestTokenToWethExecutionPrice(
        TokenToWethExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) internal pure returns (uint256 bestPriceIndex) {
        ///@notice If the order is a buy order, set the initial best price at 0.
        if (buyOrder) {
            uint256 bestPrice = 0;

            ///@notice For each exectution price in the executionPrices array.
            for (uint256 i = 0; i < executionPrices.length; ) {
                uint256 executionPrice = executionPrices[i].price;

                ///@notice If the execution price is better than the best exectuion price, update the bestPriceIndex.
                if (executionPrice < bestPrice && executionPrice != 0) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }

                unchecked {
                    ++i;
                }
            }
        } else {
            ///@notice If the order is a sell order, set the initial best price at max uint256.
            uint256 bestPrice = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            for (uint256 i = 0; i < executionPrices.length; ) {
                uint256 executionPrice = executionPrices[i].price;

                ///@notice If the execution price is better than the best exectuion price, update the bestPriceIndex.
                if (executionPrice > bestPrice && executionPrice != 0) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }

                unchecked {
                    ++i;
                }
            }
        }
    }

    ///@notice Function to execute a single Token To Weth order.
    ///@param order - The order to be executed.
    ///@param executionPrice - The best priced TokenToWethExecutionPrice to execute the order on.
    function _executeTokenToWethOrder(
        OrderBook.Order memory order,
        TokenToWethExecutionPrice memory executionPrice
    ) internal returns (uint256, uint256) {
        ///@notice Get the Uniswap V3 pool fee on the lp address for the batch.
        uint24 fee = _getUniV3Fee(executionPrice.lpAddressAToWeth);

        ///@notice Swap the batch amountIn on the batch lp address and send the weth back to the contract.
        uint128 amountOutWeth = uint128(
            _swap(
                order.tokenIn,
                WETH,
                executionPrice.lpAddressAToWeth,
                order.feeIn,
                order.quantity,
                order.amountOutMin,
                address(this),
                order.owner
            )
        );

        ///@notice Retrieve the protocol fee for the total amount out.
        uint128 protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

        ///@notice Get the conveyor and beacon reward from the total amount out.
        (uint128 conveyorReward, uint128 beaconReward) = _calculateReward(
            protocolFee,
            amountOutWeth
        );

        ///@notice Increment the conveyor balance by the conveyor reward
        conveyorBalance += conveyorReward;

        return (
            uint256(amountOutWeth - (beaconReward + conveyorReward)),
            uint256(beaconReward)
        );
    }

    ///@notice Function to execute multiple batch orders from TokenIn to Weth.
    ///@param tokenToWethBatchOrders Array of TokenToWeth batches.
    ///@param maxBeaconReward The maximum funds the beacon will recieve after execution.
    function _executeTokenToWethBatchOrders(
        TokenToWethBatchOrder[] memory tokenToWethBatchOrders,
        uint128 maxBeaconReward
    ) internal {
        ///@notice Instantiate total beacon reward
        uint256 totalBeaconReward;

        ///@notice Iterate through each tokenToWethBatchOrder
        for (uint256 i = 0; i < tokenToWethBatchOrders.length; ) {
            ///@notice Set batch to the i'th batch order
            TokenToWethBatchOrder memory batch = tokenToWethBatchOrders[i];
            ///@notice If 0 order's exist in the batch continue
            if (batch.batchLength > 0) {
                ///@notice Execute the TokenIn to Weth batch
                (
                    uint256 amountOut,
                    uint256 beaconReward
                ) = _executeTokenToWethBatch(batch);

                ///@notice Accumulate the totalBeaconReward
                totalBeaconReward += beaconReward;

                ///@notice OwnerShares represents the % of ownership over the out amount post execution
                uint256[] memory ownerShares = batch.ownerShares;

                ///@notice amountIn represents the total amountIn on the batch for all orders
                uint256 amountIn = batch.amountIn;

                ///@notice batchOrderLength represents the total amount of orders in the batch
                uint256 batchOrderLength = batch.batchLength;

                ///@notice Iterate through each order in the batch
                for (uint256 j = 0; j < batchOrderLength; ) {
                    ///@notice Calculate how much to pay each user from the shares they own
                    uint128 orderShare = ConveyorMath.divUI(
                        ownerShares[j],
                        amountIn
                    );

                    ///@notice Multiply the amountOut*orderShare to get the total amount out owned by the order
                    uint256 orderPayout = ConveyorMath.mul64I(
                        orderShare,
                        amountOut
                    );

                    ///@notice Send the order owner their orderPayout
                    IERC20(WETH).transfer(batch.batchOwners[j], orderPayout);

                    unchecked {
                        ++j;
                    }
                }
            }

            unchecked {
                ++i;
            }
        }

        /**@notice If the maxBeaconReward is greater than the totalBeaconReward then keep the totalBeaconReward else set totalBeaconReward
        to the maxBeaconReward
        */
        totalBeaconReward = maxBeaconReward > totalBeaconReward
            ? totalBeaconReward
            : maxBeaconReward;

        ///@notice Unwrap the WETH to send to the beacon.
        IWETH(WETH).withdraw(totalBeaconReward);

        ///@notice Send the Total Reward to the beacon.
        safeTransferETH(msg.sender, totalBeaconReward);
    }

    ///@notice Function to Execute a single batch of TokenIn to Weth Orders.
    ///@param batch A single batch of TokenToWeth orders
    function _executeTokenToWethBatch(TokenToWethBatchOrder memory batch)
        internal
        returns (uint256, uint256)
    {
        ///@notice Get the Uniswap V3 pool fee on the lp address for the batch.
        uint24 fee = _getUniV3Fee(batch.lpAddress);

        ///@notice Swap the batch amountIn on the batch lp address and send the weth back to the contract.
        uint128 amountOutWeth = uint128(
            _swap(
                batch.tokenIn,
                WETH,
                batch.lpAddress,
                fee,
                batch.amountIn,
                batch.amountOutMin,
                address(this),
                address(this)
            )
        );

        ///@notice Retrieve the protocol fee for the total amount out.
        uint128 protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

        ///@notice Get the conveyor and beacon reward from the total amount out.
        (uint128 conveyorReward, uint128 beaconReward) = _calculateReward(
            protocolFee,
            amountOutWeth
        );

        ///@notice Increment the conveyor balance by the conveyor reward
        conveyorBalance += conveyorReward;

        return (
            uint256(amountOutWeth - (beaconReward + conveyorReward)),
            uint256(beaconReward)
        );
    }

    ///@notice Initializes all routes from tokenA to Weth -> Weth to tokenB and returns an array of all combinations as ExectionPrice[]
    ///@param orders - Array of orders that are being evaluated for execution.
    function _initializeTokenToWethExecutionPrices(
        OrderBook.Order[] memory orders
    ) internal view returns (TokenToWethExecutionPrice[] memory, uint128) {
        ///@notice Get all prices for the pairing
        (
            SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = _getAllPrices(orders[0].tokenIn, WETH, orders[0].feeIn);

        ///@notice Initialize a new TokenToWethExecutionPrice array to store prices.
        TokenToWethExecutionPrice[]
            memory executionPrices = new TokenToWethExecutionPrice[](
                spotReserveAToWeth.length
            );

        ///@notice Scoping to avoid stack too deep.
        {
            ///@notice For each spot reserve, initialize a token to weth execution price.
            for (uint256 i = 0; i < spotReserveAToWeth.length; ++i) {
                executionPrices[i] = TokenToWethExecutionPrice(
                    spotReserveAToWeth[i].res0,
                    spotReserveAToWeth[i].res1,
                    spotReserveAToWeth[i].spotPrice,
                    lpAddressesAToWeth[i]
                );
            }
        }

        ///@notice Calculate the max beacon reward from the spot reserves.
        uint128 maxBeaconReward = calculateMaxBeaconReward(
            spotReserveAToWeth,
            orders,
            false
        );

        return (executionPrices, maxBeaconReward);
    }

    ///@notice Initialize a new token to weth batch order
    /**@param initArrayLength - The maximum amount of orders that will be included in the batch. This is used to initalize
    arrays in the token to weth batch order struct. */
    ///@param tokenIn - TokenIn for the batch order.
    ///@param lpAddressAToWeth - LP address for the tokenIn/Weth pairing.
    ///@return tokenToWethBatchOrder - Returns a new empty token to weth batch order.
    function _initializeNewTokenToWethBatchOrder(
        uint256 initArrayLength,
        address tokenIn,
        address lpAddressAToWeth
    ) internal pure returns (TokenToWethBatchOrder memory) {
        ///@notice initialize a new batch order
        return
            TokenToWethBatchOrder(
                ///@notice initialize batch length to 0
                0,
                ///@notice initialize amountIn
                0,
                ///@notice initialize amountOutMin
                0,
                ///@notice add the token in
                tokenIn,
                ///@notice initialize A to weth lp
                lpAddressAToWeth,
                ///@notice initialize batchOwners
                new address[](initArrayLength),
                ///@notice initialize ownerShares
                new uint256[](initArrayLength),
                ///@notice initialize orderIds
                new bytes32[](initArrayLength)
            );
    }

    ///@notice Function to batch multiple token to weth orders together.
    ///@param orders - Array of orders to be batched into the most efficient ordering.
    ///@param executionPrices - Array of execution prices available to the batch orders. The batch order will be placed on the best execution price.
    ///@return  tokenToWethBatchOrders - Returns an array of TokenToWethBatchOrder.
    function _batchTokenToWethOrders(
        OrderBook.Order[] memory orders,
        TokenToWethExecutionPrice[] memory executionPrices
    ) internal returns (TokenToWethBatchOrder[] memory) {
        ///@notice Create a new token to weth batch order.
        TokenToWethBatchOrder[]
            memory tokenToWethBatchOrders = new TokenToWethBatchOrder[](
                orders.length
            );

        ///@notice Cache the first order in the array.
        OrderBook.Order memory firstOrder = orders[0];

        ///@notice Check if the order is a buy or sell to assign the buy/sell status for the batch.
        bool buyOrder = _buyOrSell(firstOrder);

        ///@notice Assign the batch's tokenIn.
        address batchOrderTokenIn = firstOrder.tokenIn;

        ///@notice Create a variable to track the best execution price in the array of execution prices.
        uint256 currentBestPriceIndex = _findBestTokenToWethExecutionPrice(
            executionPrices,
            buyOrder
        );

        ///@notice Initialize a new token to weth batch order.
        TokenToWethBatchOrder
            memory currentTokenToWethBatchOrder = _initializeNewTokenToWethBatchOrder(
                orders.length,
                batchOrderTokenIn,
                executionPrices[currentBestPriceIndex].lpAddressAToWeth
            );

        ///@notice Initialize a variable to keep track of how many batch orders there are.
        uint256 currentTokenToWethBatchOrdersIndex = 0;

        ///@notice For each order in the orders array.
        for (uint256 i = 0; i < orders.length; ) {
            ///@notice Get the index of the best exectuion price.
            uint256 bestPriceIndex = _findBestTokenToWethExecutionPrice(
                executionPrices,
                buyOrder
            );

            ///@notice if the best price has changed since the last order, add the batch order to the array and update the best price index.
            if (i > 0 && currentBestPriceIndex != bestPriceIndex) {
                ///@notice Add the current batch order to the batch orders array.
                tokenToWethBatchOrders[
                    currentTokenToWethBatchOrdersIndex
                ] = currentTokenToWethBatchOrder;

                ///@notice Increment the amount of to current token to weth batch orders index
                ++currentTokenToWethBatchOrdersIndex;

                ///@notice Update the index of the best execution price.
                currentBestPriceIndex = bestPriceIndex;

                ///@notice Initialize a new batch order.
                currentTokenToWethBatchOrder = _initializeNewTokenToWethBatchOrder(
                    orders.length,
                    batchOrderTokenIn,
                    executionPrices[bestPriceIndex].lpAddressAToWeth
                );
            }

            ///@notice Get the current order.
            OrderBook.Order memory currentOrder = orders[i];

            ///@notice Check that the order meets execution price.
            if (
                _orderMeetsExecutionPrice(
                    currentOrder.price,
                    executionPrices[bestPriceIndex].price,
                    buyOrder
                )
            ) {
                ///@notice Check that the order can execute without hitting slippage.
                if (
                    _orderCanExecute(
                        executionPrices[bestPriceIndex].price,
                        currentOrder.quantity,
                        currentOrder.amountOutMin
                    )
                ) {
                    ///@notice Transfer the tokenIn from the user's wallet to the contract. If the transfer fails, cancel the order.
                    bool success = transferTokensToContract(currentOrder);

                    if (success) {
                        ///@notice Get the batch length of the current batch order.
                        uint256 batchLength = currentTokenToWethBatchOrder
                            .batchLength;

                        ///@notice Add the order to the current batch order.
                        currentTokenToWethBatchOrder.amountIn += currentOrder
                            .quantity;

                        ///@notice Add the owner of the order to the batchOwners.
                        currentTokenToWethBatchOrder.batchOwners[
                            batchLength
                        ] = currentOrder.owner;

                        ///@notice Add the order quantity of the order to ownerShares.
                        currentTokenToWethBatchOrder.ownerShares[
                            batchLength
                        ] = currentOrder.quantity;

                        ///@notice Add the orderId to the batch order.
                        currentTokenToWethBatchOrder.orderIds[
                            batchLength
                        ] = currentOrder.orderId;

                        ///@notice Add the amountOutMin to the batch order.
                        currentTokenToWethBatchOrder
                            .amountOutMin += currentOrder.amountOutMin;

                        ///@notice Increment the batch length.
                        ++currentTokenToWethBatchOrder.batchLength;

                        ///@notice Update the best execution price.
                        (
                            executionPrices[bestPriceIndex]
                        ) = simulateTokenToWethPriceChange(
                            uint128(currentOrder.quantity),
                            executionPrices[bestPriceIndex]
                        );
                    }
                } else {
                    ///@notice If the order can not execute due to slippage, revert to notify the off-chain executor.
                    revert OrderHasInsufficientSlippage(currentOrder.orderId);
                }

                revert OrderDoesNotMeetExecutionPrice(currentOrder.orderId);
            }

            unchecked {
                ++i;
            }
        }

        ///@notice Add the last batch to the tokenToWethBatchOrders array.
        tokenToWethBatchOrders[
            currentTokenToWethBatchOrdersIndex
        ] = currentTokenToWethBatchOrder;

        return tokenToWethBatchOrders;
    }

    ///@notice Transfer the order quantity to the contract.
    ///@return success - Boolean to indicate if the transfer was successful.
    function transferTokensToContract(OrderBook.Order memory order)
        internal
        returns (bool success)
    {
        try
            IERC20(order.tokenIn).transferFrom(
                order.owner,
                address(this),
                order.quantity
            )
        {} catch {
            ///@notice Revert on token transfer failure.
            revert TokenTransferFailed(order.orderId);
        }
        return true;
    }

    ///@notice Function to execute a swap from TokenToWeth for an order.
    ///@param executionPrice - The best priced TokenToTokenExecutionPrice for the order to be executed on.
    ///@param order - The order to be executed.
    ///@return amountOutWeth - The amountOut in Weth after the swap.
    function _executeSwapTokenToWethOrder(
        TokenToTokenExecutionPrice memory executionPrice,
        OrderBook.Order memory order
    ) internal returns (uint128 amountOutWeth) {
        ///@notice Cache the liquidity pool address.
        address lpAddressAToWeth = executionPrice.lpAddressAToWeth;

        ///@notice Cache the order Quantity.
        uint256 orderQuantity = order.quantity;

        uint24 feeIn = order.feeIn;
        address tokenIn = order.tokenIn;

        ///@notice Calculate the amountOutMin for the tokenA to Weth swap.
        uint256 batchAmountOutMinAToWeth = calculateAmountOutMinAToWeth(
            lpAddressAToWeth,
            orderQuantity,
            order.taxIn,
            feeIn,
            tokenIn
        );

        ///@notice Swap from tokenA to Weth.
        amountOutWeth = uint128(
            _swap(
                tokenIn,
                WETH,
                lpAddressAToWeth,
                feeIn,
                order.quantity,
                batchAmountOutMinAToWeth,
                address(this),
                order.owner
            )
        );

        ///@notice Take out fees from the amountOut.
        uint128 protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

        ///@notice Calculate the conveyorReward and executor reward.
        (uint128 conveyorReward, uint128 beaconReward) = _calculateReward(
            protocolFee,
            amountOutWeth
        );

        ///@notice Increment the conveyor protocol's balance of ether in the contract by the conveyorReward.
        conveyorBalance += conveyorReward;

        ///@notice Get the AmountIn for weth to tokenB.
        amountOutWeth = amountOutWeth - (beaconReward + conveyorReward);
    }

    ///@notice Helper function to calculate amountOutMin value agnostically across dexes on the first hop from tokenA to WETH.
    ///@param lpAddressAToWeth - The liquidity pool for tokenA to Weth.
    ///@param amountInOrder - The amount in on the swap.
    ///@param taxIn - The tax on the input token for the swap.
    ///@param feeIn - The fee on the swap.
    ///@param tokenIn - The address of tokenIn on the swap.
    ///@return amountOutMinAToWeth - The amountOutMin in the swap.
    function calculateAmountOutMinAToWeth(
        address lpAddressAToWeth,
        uint256 amountInOrder,
        uint16 taxIn,
        uint24 feeIn,
        address tokenIn
    ) internal returns (uint256 amountOutMinAToWeth) {
        ///@notice Check if the lp is UniV3
        if (!_lpIsNotUniV3(lpAddressAToWeth)) {
            ///@notice 1000==100% so divide amountInOrder *taxIn by 10**5 to adjust to correct base
            uint256 amountInBuffer = (amountInOrder * taxIn) / 10**5;
            uint256 amountIn = amountInOrder - amountInBuffer;

            ///@notice Calculate the amountOutMin for the swap.
            amountOutMinAToWeth = iQuoter.quoteExactInputSingle(
                tokenIn,
                WETH,
                feeIn,
                amountIn,
                0
            );
        } else {
            ///@notice Otherwise if the lp is a UniV2 LP.

            ///@notice Get the reserves from the pool.
            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(
                lpAddressAToWeth
            ).getReserves();

            ///@notice Initialize the reserve0 and reserve1 depending on if Weth is token0 or token1.
            if (WETH == IUniswapV2Pair(lpAddressAToWeth).token0()) {
                uint256 amountInBuffer = (amountInOrder * taxIn) / 10**5;
                uint256 amountIn = amountInOrder - amountInBuffer;
                amountOutMinAToWeth = getAmountOut(
                    amountIn,
                    uint256(reserve1),
                    uint256(reserve0)
                );
            } else {
                uint256 amountInBuffer = (amountInOrder * taxIn) / 10**5;
                uint256 amountIn = amountInOrder - amountInBuffer;
                amountOutMinAToWeth = getAmountOut(
                    amountIn,
                    uint256(reserve0),
                    uint256(reserve1)
                );
            }
        }
    }

    ///@notice Function to get the amountOut from a UniV2 lp.
    ///@param amountIn - AmountIn for the swap.
    ///@param reserveIn - tokenIn reserve for the swap.
    ///@param reserveOut - tokenOut reserve for the swap.
    ///@return amountOut - AmountOut from the given parameters.
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        if (amountIn == 0) {
            revert InsufficientInputAmount();
        }

        if (reserveIn == 0) {
            revert InsufficientLiquidity();
        }

        if (reserveOut == 0) {
            revert InsufficientLiquidity();
        }

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + (amountInWithFee);
        amountOut = numerator / denominator;
    }

    ///@notice Function to retrieve the buy/sell status of a single order.
    ///@param order Order to determine buy/sell status on.
    ///@return bool Boolean indicating the buy/sell status of the order.
    function _buyOrSell(OrderBook.Order memory order)
        internal
        pure
        returns (bool)
    {
        if (order.buy) {
            return true;
        } else {
            return false;
        }
    }

    ///@notice Function to simulate the price change from TokanA to Weth on an amount into the pool
    ///@param alphaX The amount supplied to the TokenA reserves of the pool.
    ///@param executionPrice The TokenToWethExecutionPrice to simulate the price change on.
    function simulateTokenToWethPriceChange(
        uint128 alphaX,
        TokenToWethExecutionPrice memory executionPrice
    ) internal returns (TokenToWethExecutionPrice memory) {
        ///@notice Cache the liquidity pool address
        address pool = executionPrice.lpAddressAToWeth;

        ///@notice Cache token0 and token1 from the pool address
        address token0 = IUniswapV2Pair(pool).token0();
        address token1 = IUniswapV2Pair(pool).token1();

        ///@notice Get the decimals of the tokenIn on the swap
        uint8 tokenInDecimals = token1 == WETH
            ? IERC20(token0).decimals()
            : IERC20(token1).decimals();

        ///@notice Convert to 18 decimals to have correct price change on the reserve quantities in common 18 decimal form
        uint128 amountIn = tokenInDecimals <= 18
            ? uint128(alphaX * 10**(18 - tokenInDecimals))
            : uint128(alphaX / (10**(tokenInDecimals - 18)));

        ///@notice Simulate the price change on the 18 decimal amountIn quantity, and set executionPrice struct to the updated quantities.
        (
            executionPrice.price,
            executionPrice.aToWethReserve0,
            executionPrice.aToWethReserve1,

        ) = _simulateAToBPriceChange(
            amountIn,
            executionPrice.aToWethReserve0,
            executionPrice.aToWethReserve1,
            pool,
            true
        );

        return executionPrice;
    }

    ///@notice Function to simulate the AToWeth price change on a pair.
    ///@param alphaX - The input quantity to simulate the price change on.
    ///@param executionPrice - The TokenToTokenExecutionPrice to simulate the price change on.
    function _simulateAToWethPriceChange(
        uint128 alphaX,
        TokenToTokenExecutionPrice memory executionPrice
    )
        internal
        returns (
            uint256 newSpotPriceA,
            uint128 newReserveAToken,
            uint128 newReserveAWeth,
            uint128 amountOut
        )
    {
        ///@notice Cache the Reserves and the pool address on the liquidity pool
        uint128 reserveAToken = executionPrice.aToWethReserve0;
        uint128 reserveAWeth = executionPrice.aToWethReserve1;
        address poolAddressAToWeth = executionPrice.lpAddressAToWeth;

        ///@notice Simulate the price change from TokenIn To Weth and return the values.
        (
            newSpotPriceA,
            newReserveAToken,
            newReserveAWeth,
            amountOut
        ) = _simulateAToBPriceChange(
            alphaX,
            reserveAToken,
            reserveAWeth,
            poolAddressAToWeth,
            true
        );
    }

    ///@notice Function to simulate the WethToB price change on a pair.
    ///@param alphaX - The input quantity to simulate the price change on.
    ///@param executionPrice - The TokenToTokenExecutionPrice to simulate the price change on.
    function _simulateWethToBPriceChange(
        uint128 alphaX,
        TokenToTokenExecutionPrice memory executionPrice
    )
        internal
        returns (
            uint256 newSpotPriceB,
            uint128 newReserveBWeth,
            uint128 newReserveBToken
        )
    {
        ///@notice Cache the reserve values, and the pool address on the token pair.
        uint128 reserveBWeth = executionPrice.wethToBReserve0;
        uint128 reserveBToken = executionPrice.wethToBReserve1;
        address poolAddressWethToB = executionPrice.lpAddressWethToB;

        ///@notice Simulate the Weth to TokenOut price change and return the values.
        (
            newSpotPriceB,
            newReserveBWeth,
            newReserveBToken,

        ) = _simulateAToBPriceChange(
            alphaX,
            reserveBToken,
            reserveBWeth,
            poolAddressWethToB,
            false
        );
    }

    /// @notice Function to calculate the price change of a token pair on a specified input quantity.
    /// @param alphaX Quantity to be added into the TokenA reserves
    /// @param reserveA Reserves of tokenA
    /// @param reserveB Reserves of tokenB
    function _simulateAToBPriceChange(
        uint128 alphaX,
        uint128 reserveA,
        uint128 reserveB,
        address pool,
        bool isTokenToWeth
    )
        internal
        returns (
            uint256,
            uint128,
            uint128,
            uint128
        )
    {
        ///@notice Initialize Array to hold the simulated reserve quantities.
        uint128[] memory newReserves = new uint128[](2);

        ///@notice If the liquidity pool is not Uniswap V3 then the calculation is different.
        if (_lpIsNotUniV3(pool)) {
            unchecked {
                ///@notice Supply alphaX to the tokenA reserves.
                uint256 denominator = reserveA + alphaX;

                ///@notice Numerator is the new tokenB reserve quantity i.e k/(reserveA+alphaX)
                uint256 numerator = FullMath.mulDiv(
                    uint256(reserveA),
                    uint256(reserveB),
                    denominator
                );

                ///@notice Spot price = reserveB/reserveA
                uint256 spotPrice = uint256(
                    ConveyorMath.divUI(numerator, denominator)
                ) << 64;

                ///@notice Update update the new reserves array to the simulated reserve values.
                newReserves[0] = uint128(denominator);
                newReserves[1] = uint128(numerator);

                ///@notice Set the amountOut of the swap on alphaX input amount.
                uint128 amountOut = uint128(
                    getAmountOut(alphaX, reserveA, reserveB)
                );

                return (spotPrice, newReserves[0], newReserves[1], amountOut);
            }
            ///@notice If the liquidity pool is Uniswap V3.
        } else {
            ///@notice Get the Uniswap V3 spot price change and amountOut from the simuulating alphaX on the pool.
            (
                uint128 spotPrice64x64,
                uint128 amountOut
            ) = calculateNextSqrtPriceX96(isTokenToWeth, pool, alphaX);

            ///@notice Set the reserves to 0 since they are not required for Uniswap V3
            newReserves[0] = 0;
            newReserves[1] = 0;

            ///@notice Left shift 64 to adjust spot price to 128.128 fixed point
            uint256 spotPrice = uint256(spotPrice64x64) << 64;

            return (spotPrice, newReserves[0], newReserves[1], amountOut);
        }
    }

    ///@notice Helper function to calculate precise price change in a uni v3 pool after alphaX value is added to the liquidity on either token
    ///@param isTokenToWeth boolean indicating whether swap is happening from token->weth or weth->token respectively
    ///@param pool address of the Uniswap v3 pool to simulate the price change on
    ///@param alphaX quantity to be added to the liquidity of tokenIn
    ///@return spotPrice 64.64 fixed point spot price after the input quantity has been added to the pool
    ///@return amountOut quantity recieved on the out token post swap
    function calculateNextSqrtPriceX96(
        bool isTokenToWeth,
        address pool,
        uint256 alphaX
    ) internal returns (uint128 spotPrice, uint128 amountOut) {
        ///@notice sqrtPrice Fixed point 64.96 form token1/token0 exchange rate
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();

        ///@notice Concentrated liquidity in current price tick range
        uint128 liquidity = IUniswapV3Pool(pool).liquidity();

        ///@notice Get token0/token1 from the pool
        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();

        ///@notice Boolean indicating whether weth is token0 or token1
        bool wethIsToken0 = token0 == WETH ? true : false;

        ///@notice Instantiate nextSqrtPriceX96 to hold adjusted price after simulated swap
        uint160 nextSqrtPriceX96;

        ///@notice Cache pool fee
        uint24 fee = IUniswapV3Pool(pool).fee();

        ///@notice Conditional whether swap is happening from tokenToWeth or wethToToken
        if (isTokenToWeth) {
            if (wethIsToken0) {
                ///@notice If weth is token0 and swap is happening from tokenToWeth ==> token1 = token & alphaX is in token1
                ///@notice Assign amountOut to hold output amount in Weth for subsequent simulation calls
                amountOut = uint128(
                    iQuoter.quoteExactInputSingle(token1, WETH, fee, alphaX, 0)
                );

                ///@notice tokenIn is token1 therefore 0for1 is false & alphaX is input into tokenIn liquidity ==> rounding down
                nextSqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtPriceX96,
                    liquidity,
                    alphaX,
                    false
                );

                ///@notice Convert output to 64.64 fixed point representation
                uint128 sqrtSpotPrice64x64 = ConveyorTickMath.fromX96(
                    nextSqrtPriceX96
                );

                ///@notice sqrtSpotPrice64x64 == token1/token0 spot, since token1 is our tokenIn take the inverse of sqrtSpotPrice64x64 and square it to be in standard form usable for two hop finalSpot calculation
                spotPrice = ConveyorMath.mul64x64(
                    ConveyorMath.div64x64(uint128(1) << 64, sqrtSpotPrice64x64),
                    ConveyorMath.div64x64(uint128(1) << 64, sqrtSpotPrice64x64)
                );
            } else {
                ///@notice weth is token1 therefore tokenIn is token0, assign amountOut to wethOut value for subsequent simulations
                amountOut = uint128(
                    iQuoter.quoteExactInputSingle(token0, WETH, fee, alphaX, 0)
                );

                ///@notice calculate nextSqrtPriceX96 price change on wethOutAmount add false since we are removing the weth liquidity from the pool
                nextSqrtPriceX96 = SqrtPriceMath
                    .getNextSqrtPriceFromAmount1RoundingDown(
                        sqrtPriceX96,
                        liquidity,
                        amountOut,
                        false
                    );

                ///@notice Since weth is token1 we have the correct form of sqrtPrice i.e token1/token0 spot, so just convert to 64.64 and square it
                uint128 sqrtSpotPrice64x64 = ConveyorTickMath.fromX96(
                    nextSqrtPriceX96
                );

                ///@notice sqrtSpotPrice64x64 == token1/token0 which is the correct direction so, simply square the 64.64 sqrt price.
                spotPrice = ConveyorMath.mul64x64(
                    sqrtSpotPrice64x64,
                    sqrtSpotPrice64x64
                );
            }
        } else {
            ///@notice isTokenToWeth =false ==> we are exchanging weth -> token
            if (wethIsToken0) {
                ///@notice since weth is token0 set amountOut to token quoted amount out on alphaX Weth into the pool
                amountOut = uint128(
                    iQuoter.quoteExactInputSingle(WETH, token1, fee, alphaX, 0)
                );

                ///@notice amountOut is in our out token, so set nextSqrtPriceX96 to change in price on amountOut value
                ///@notice weth is token 0 so set add to false since we are removing token1 liquidity from the pool
                nextSqrtPriceX96 = SqrtPriceMath
                    .getNextSqrtPriceFromAmount1RoundingDown(
                        sqrtPriceX96,
                        liquidity,
                        amountOut,
                        false
                    );
                ///@notice Since token0 = weth token1/token0 is the proper exchange rate so convert to 64.64 and square to yield the spot price
                uint128 sqrtSpotPrice64x64 = ConveyorTickMath.fromX96(
                    nextSqrtPriceX96
                );

                ///@notice sqrtSpotPrice64x64 == token1/token0 which is the correct direction so, simply square the 64.64 sqrt price.
                spotPrice = ConveyorMath.mul64x64(
                    sqrtSpotPrice64x64,
                    sqrtSpotPrice64x64
                );
            } else {
                ///@notice weth == token1 so initialize amountOut on weth-token0
                amountOut = uint128(
                    iQuoter.quoteExactInputSingle(WETH, token0, fee, alphaX, 0)
                );

                ///@notice set nextSqrtPriceX96 to change on Input alphaX which will be in Weth, since weth is token1 0To1=false
                nextSqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtPriceX96,
                    liquidity,
                    alphaX,
                    false
                );

                ///@notice Convert to 64.64.
                uint128 sqrtSpotPrice64x64 = ConveyorTickMath.fromX96(
                    nextSqrtPriceX96
                );

                ///@notice sqrtSpotPrice64x64 == token1/token0 spot, since token1 is our tokenIn take the inverse of sqrtSpotPrice64x64 and square it to be in standard form usable for two hop finalSpot calculation
                spotPrice = ConveyorMath.mul64x64(
                    ConveyorMath.div64x64(uint128(1) << 64, sqrtSpotPrice64x64),
                    ConveyorMath.div64x64(uint128(1) << 64, sqrtSpotPrice64x64)
                );
            }
        }
    }

    /// @notice Function to determine if an order meets the execution price.
    ///@param orderPrice The Spot price for execution of the order.
    ///@param executionPrice The current execution price of the best prices lp.
    ///@param buyOrder The buy/sell status of the order.
    function _orderMeetsExecutionPrice(
        uint256 orderPrice,
        uint256 executionPrice,
        bool buyOrder
    ) internal pure returns (bool) {
        if (buyOrder) {
            return executionPrice <= orderPrice;
        } else {
            return executionPrice >= orderPrice;
        }
    }

    ///@notice Checks if order can complete without hitting slippage
    ///@param spot_price The spot price of the liquidity pool.
    ///@param order_quantity The input quantity of the order.
    ///@param amountOutMin The slippage set by the order owner.
    function _orderCanExecute(
        uint256 spot_price,
        uint256 order_quantity,
        uint256 amountOutMin
    ) internal pure returns (bool) {
        return ConveyorMath.mul128I(spot_price, order_quantity) >= amountOutMin;
    }

    ///@notice Function to withdraw owner fee's accumulated
    function withdrawConveyorFees() external onlyOwner {
        safeTransferETH(owner, conveyorBalance);
        conveyorBalance = 0;
    }
}
