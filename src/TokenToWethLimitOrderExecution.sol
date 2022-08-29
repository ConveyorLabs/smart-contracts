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
import "./SwapRouter.sol";
import "./ConveyorErrors.sol";
import "../lib/libraries/Uniswap/FullMath.sol";
import "../lib/interfaces/token/IWETH.sol";
import "../lib/interfaces/uniswap-v3/IQuoter.sol";
import "../lib/libraries/ConveyorTickMath.sol";
import "./interfaces/IOrderRouter.sol";
import "./LimitOrderBatcher.sol";

/// @title SwapRouter
/// @author LeytonTaylor, 0xKitsune, Conveyor Labs
/// @notice Limit Order contract to execute existing limit orders within the OrderBook contract.
contract TokenToWethLimitOrderExecution is LimitOrderBatcher {
    // ========================================= Modifiers =============================================
    address owner;

    ///@notice Modifier function to only allow the owner of the contract to call specific functions
    ///@dev Functions with onlyOwner: withd rawConveyorFees, transferOwnership.
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert MsgSenderIsNotOwner();
        }

        _;
    }

    ///@notice Conveyor funds balance in the contract.
    uint256 conveyorBalance;

    // ========================================= Immutables  =============================================

    ///@notice The USD pegged token address for the chain.
    address immutable USDC;

    ///@notice IQuoter instance to quote the amountOut for a given amountIn on a UniV3 pool.
    IQuoter immutable iQuoter;

    address immutable ORDER_ROUTER;

    // ========================================= Constructor =============================================

    ///@param _weth - Address of the wrapped native token for the chain.
    ///@param _usdc - Address of the USD pegged token for the chain.
    ///@param _quoterAddress - Address for the IQuoter instance.
    ///@param _orderRouter - Address of the SwapRouter contract.
    constructor(
        address _weth,
        address _usdc,
        address _quoterAddress,
        address _orderRouter
    ) LimitOrderBatcher(_weth, _quoterAddress, _orderRouter) {
        ORDER_ROUTER = _orderRouter;
        iQuoter = IQuoter(_quoterAddress);
        USDC = _usdc;
        owner = msg.sender;
    }

    // ========================================= FUNCTIONS =============================================

    // ==================== Order Execution Functions =========================

    ///@notice Function to execute a batch of Token to Weth Orders.
    function executeTokenToWethOrders(OrderBook.Order[] memory orders)
        external
    {
        ///@notice Get all of the execution prices on TokenIn to Weth for each dex.
        (
            SwapRouter.TokenToWethExecutionPrice[] memory executionPrices,
            uint128 maxBeaconReward
        ) = _initializeTokenToWethExecutionPrices(orders);

        ///@notice Get the batch of order's targeted on the best priced Lp's
        SwapRouter.TokenToWethBatchOrder[]
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
            SwapRouter.TokenToWethExecutionPrice[] memory executionPrices,
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
        SwapRouter.TokenToWethExecutionPrice memory executionPrice
    ) internal {
        ///@notice Execute the TokenIn to Weth order.
        (uint256 amountOut, uint256 beaconReward) = _executeTokenToWethOrder(
            order,
            executionPrice
        );

        ///@notice Transfer the tokenOut amount to the order owner.
        IOrderRouter(ORDER_ROUTER).transferTokensOutToOwner(
            order.owner,
            amountOut,
            WETH
        );

        /**@notice If the maxBeaconReward is greater than the beaconReward then keep the beaconReward else set beaconReward
        to the maxBeaconReward
        */
        beaconReward = maxBeaconReward > beaconReward
            ? beaconReward
            : maxBeaconReward;

        ///@notice Transfer the accumulated reward to the off-chain executor.
        IOrderRouter(ORDER_ROUTER).transferBeaconReward(
            beaconReward,
            tx.origin,
            WETH
        );
    }

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

    ///@notice Function to execute a single Token To Weth order.
    ///@param order - The order to be executed.
    ///@param executionPrice - The best priced TokenToWethExecutionPrice to execute the order on.
    function _executeTokenToWethOrder(
        OrderBook.Order memory order,
        SwapRouter.TokenToWethExecutionPrice memory executionPrice
    ) internal returns (uint256, uint256) {
        ///@notice Swap the batch amountIn on the batch lp address and send the weth back to the contract.
        uint128 amountOutWeth = uint128(
            IOrderRouter(ORDER_ROUTER).swap(
                order.tokenIn,
                WETH,
                executionPrice.lpAddressAToWeth,
                order.feeIn,
                order.quantity,
                order.amountOutMin,
                ORDER_ROUTER,
                order.owner
            )
        );

        ///@notice Retrieve the protocol fee for the total amount out.
        uint128 protocolFee = IOrderRouter(ORDER_ROUTER).calculateFee(
            amountOutWeth,
            USDC,
            WETH
        );

        ///@notice Get the conveyor and beacon reward from the total amount out.
        (uint128 conveyorReward, uint128 beaconReward) = IOrderRouter(
            ORDER_ROUTER
        ).calculateReward(protocolFee, amountOutWeth);

        ///@notice Increment the conveyor balance by the conveyor reward
        conveyorBalance += conveyorReward;

        return (
            uint256(amountOutWeth - (beaconReward + conveyorReward)),
            uint256(beaconReward)
        );
    }

    ///@notice Helper function to get Uniswap V3 fee from a pool address.
    ///@param lpAddress - Address of the lp.
    ///@return fee The fee on the lp.
    function _getUniV3Fee(address lpAddress) internal returns (uint24 fee) {
        if (!_lpIsNotUniV3(lpAddress)) {
            return IUniswapV3Pool(lpAddress).fee();
        } else {
            return uint24(0);
        }
    }

    ///@notice Function to execute multiple batch orders from TokenIn to Weth.
    ///@param tokenToWethBatchOrders Array of TokenToWeth batches.
    ///@param maxBeaconReward The maximum funds the beacon will recieve after execution.
    function _executeTokenToWethBatchOrders(
        SwapRouter.TokenToWethBatchOrder[] memory tokenToWethBatchOrders,
        uint128 maxBeaconReward
    ) internal {
        ///@notice Instantiate total beacon reward
        uint256 totalBeaconReward;

        ///@notice Iterate through each tokenToWethBatchOrder
        for (uint256 i = 0; i < tokenToWethBatchOrders.length; ) {
            ///@notice Set batch to the i'th batch order
            SwapRouter.TokenToWethBatchOrder
                memory batch = tokenToWethBatchOrders[i];
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
                    IOrderRouter(ORDER_ROUTER).transferTokensOutToOwner(
                        batch.batchOwners[j],
                        orderPayout,
                        WETH
                    );

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

        ///@notice Transfer the accumulated reward to the off-chain executor.
        IOrderRouter(ORDER_ROUTER).transferBeaconReward(
            totalBeaconReward,
            tx.origin,
            WETH
        );
    }

    ///@notice Function to Execute a single batch of TokenIn to Weth Orders.
    ///@param batch A single batch of TokenToWeth orders
    function _executeTokenToWethBatch(
        SwapRouter.TokenToWethBatchOrder memory batch
    ) internal returns (uint256, uint256) {
        ///@notice Get the Uniswap V3 pool fee on the lp address for the batch.
        uint24 fee = _getUniV3Fee(batch.lpAddress);

        ///@notice Swap the batch amountIn on the batch lp address and send the weth back to the contract.
        uint128 amountOutWeth = uint128(
            IOrderRouter(ORDER_ROUTER).swap(
                batch.tokenIn,
                WETH,
                batch.lpAddress,
                fee,
                batch.amountIn,
                batch.amountOutMin,
                ORDER_ROUTER,
                ORDER_ROUTER
            )
        );

        ///@notice Retrieve the protocol fee for the total amount out.
        uint128 protocolFee = IOrderRouter(ORDER_ROUTER).calculateFee(
            amountOutWeth,
            USDC,
            WETH
        );

        ///@notice Get the conveyor and beacon reward from the total amount out.
        (uint128 conveyorReward, uint128 beaconReward) = IOrderRouter(
            ORDER_ROUTER
        ).calculateReward(protocolFee, amountOutWeth);

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
    )
        internal
        view
        returns (SwapRouter.TokenToWethExecutionPrice[] memory, uint128)
    {
        ///@notice Get all prices for the pairing
        (
            SwapRouter.SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = IOrderRouter(ORDER_ROUTER).getAllPrices(
                orders[0].tokenIn,
                WETH,
                orders[0].feeIn
            );

        ///@notice Initialize a new TokenToWethExecutionPrice array to store prices.
        SwapRouter.TokenToWethExecutionPrice[]
            memory executionPrices = new SwapRouter.TokenToWethExecutionPrice[](
                spotReserveAToWeth.length
            );

        ///@notice Scoping to avoid stack too deep.
        {
            ///@notice For each spot reserve, initialize a token to weth execution price.
            for (uint256 i = 0; i < spotReserveAToWeth.length; ++i) {
                executionPrices[i] = SwapRouter.TokenToWethExecutionPrice(
                    spotReserveAToWeth[i].res0,
                    spotReserveAToWeth[i].res1,
                    spotReserveAToWeth[i].spotPrice,
                    lpAddressesAToWeth[i]
                );
            }
        }

        ///@notice Calculate the max beacon reward from the spot reserves.
        uint128 maxBeaconReward = IOrderRouter(ORDER_ROUTER)
            .calculateMaxBeaconReward(spotReserveAToWeth, orders, false);

        return (executionPrices, maxBeaconReward);
    }

    ///@notice Function to execute a swap from TokenToWeth for an order.
    ///@param executionPrice - The best priced TokenToTokenExecutionPrice for the order to be executed on.
    ///@param order - The order to be executed.
    ///@return amountOutWeth - The amountOut in Weth after the swap.
    function _executeSwapTokenToWethOrder(
        SwapRouter.TokenToTokenExecutionPrice memory executionPrice,
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
            IOrderRouter(ORDER_ROUTER).swap(
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
        uint128 protocolFee = IOrderRouter(ORDER_ROUTER).calculateFee(
            amountOutWeth,
            USDC,
            WETH
        );

        ///@notice Calculate the conveyorReward and executor reward.
        (uint128 conveyorReward, uint128 beaconReward) = IOrderRouter(
            ORDER_ROUTER
        ).calculateReward(protocolFee, amountOutWeth);

        ///@notice Increment the conveyor protocol's balance of ether in the contract by the conveyorReward.
        conveyorBalance += conveyorReward;

        ///@notice Get the AmountIn for weth to tokenB.
        amountOutWeth = amountOutWeth - (beaconReward + conveyorReward);
    }

    ///@notice Function to withdraw owner fee's accumulated
    function withdrawConveyorFees() external onlyOwner {
        safeTransferETH(owner, conveyorBalance);
        conveyorBalance = 0;
    }
}
