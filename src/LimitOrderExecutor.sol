// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./SwapRouter.sol";
import "./interfaces/ILimitOrderQuoter.sol";
import "./lib/ConveyorFeeMath.sol";
import "./LimitOrderRouter.sol";
import "./interfaces/ISwapRouter.sol";

/// @title LimitOrderExecutor
/// @author 0xOsiris, 0xKitsune
/// @notice This contract handles all order execution.
contract LimitOrderExecutor is SwapRouter, ILimitOrderExecutor {
    using SafeERC20 for IERC20;
    ///====================================Immutable Storage Variables==============================================//
    address immutable WETH;
    address immutable USDC;
    address immutable LIMIT_ORDER_QUOTER;
    address public immutable LIMIT_ORDER_ROUTER;

    ///====================================Constants==============================================//
    ///@notice The Maximum Reward a beacon can receive from stoploss execution.
    ///Note:
    /*
        The STOP_LOSS_MAX_BEACON_REWARD is set to 0.06 WETH. Also Note the protocol is receiving 0.05 WETH for trades with fees surpassing the STOP_LOSS_MAX_BEACON_REWARD.
        What this means is that for stoploss orders, if the quantity of the Order surpasses the threshold such that 0.1% of the order quantity in WETH 
        is greater than 0.1 WETH total. Then the fee paid by the user will be 0.1/OrderQuantity where OrderQuantity is in terms of the amount received from the 
        output of the first Swap if WETH is not the input token. Note: For all other types of Limit Orders there is no hardcoded cap on the fee paid by the end user.
        Therefore 0.1% of the OrderQuantity will be the minimum fee paid. The fee curve reaches 0.1% in the limit, but the threshold for this 
        fee being paid is roughly $750,000. The fee paid by the user ranges from 0.5%-0.1% following a logistic curve which approaches 0.1% assymtocically in the limit
        as OrderQuantity -> infinity for all non stoploss orders. 
    */
    uint128 constant STOP_LOSS_MAX_BEACON_REWARD = 50000000000000000;

    //----------------------Modifiers------------------------------------//

    ///@notice Modifier to restrict smart contracts from calling a function.
    modifier onlyLimitOrderRouter() {
        if (msg.sender != LIMIT_ORDER_ROUTER) {
            revert MsgSenderIsNotLimitOrderRouter();
        }
        _;
    }

    bool entered = false;
    ///@notice Reentrancy modifier for transferToSandBoxRouter.
    modifier nonReentrant() {
        require(!entered, "Unauthorized Callback from ChaosRouter");
        entered = true;
        _;
        entered = false;
    }

    ///@notice Temporary owner storage variable when transferring ownership of the contract.
    address tempOwner;

    ///@notice The owner of the Order Router contract
    ///@dev The contract owner can remove the owner funds from the contract, and transfer ownership of the contract.
    address owner;

    ///@notice Conveyor funds balance in the contract.
    uint256 conveyorBalance;

    ///@notice Boolean responsible for indicating if a function has been entered when the nonReentrant modifier is used.
    bool reentrancyStatus = false;

    ///@param _weth The wrapped native token on the chain.
    ///@param _usdc Pegged stable token on the chain.
    ///@param _limitOrderQuoterAddress The address of the LimitOrderQuoter contract.
    ///@param _deploymentByteCodes The deployment bytecodes of all dex factory contracts.
    ///@param _dexFactories The Dex factory addresses.
    ///@param _isUniV2 Array of booleans indication whether the Dex is V2 architecture.
    constructor(
        address _weth,
        address _usdc,
        address _limitOrderQuoterAddress,
        bytes32[] memory _deploymentByteCodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2,
        address _gasOracle
    ) SwapRouter(_deploymentByteCodes, _dexFactories, _isUniV2) {
        require(_weth != address(0), "Invalid weth address");
        require(_usdc != address(0), "Invalid usdc address");
        require(
            _limitOrderQuoterAddress != address(0),
            "Invalid LimitOrderQuoter address"
        );
        USDC = _usdc;
        WETH = _weth;
        LIMIT_ORDER_QUOTER = _limitOrderQuoterAddress;

        LIMIT_ORDER_ROUTER = address(
            new LimitOrderRouter(_gasOracle, _weth, _usdc, address(this))
        );

        owner = msg.sender;
    }

    ///@notice Function to execute a batch of Token to Weth Orders.
    ///@param orders The orders to be executed.

    function executeTokenToWethOrders(OrderBook.LimitOrder[] memory orders)
        external
        onlyLimitOrderRouter
        returns (uint256, uint256)
    {
        ///@notice Get all of the execution prices on TokenIn to Weth for each dex.
        ///@notice Get all prices for the pairing
        (
            SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = _getAllPrices(orders[0].tokenIn, WETH, orders[0].feeIn);

        ///@notice Initialize all execution prices for the token pair.
        TokenToWethExecutionPrice[] memory executionPrices = ILimitOrderQuoter(
            LIMIT_ORDER_QUOTER
        )._initializeTokenToWethExecutionPrices(
                spotReserveAToWeth,
                lpAddressesAToWeth
            );

        ///@notice Set totalBeaconReward to 0
        uint256 totalBeaconReward = 0;

        ///@notice Set totalConveyorReward to 0
        uint256 totalConveyorReward = 0;

        for (uint256 i = 0; i < orders.length; ) {
            ///@notice Create a variable to track the best execution price in the array of execution prices.
            uint256 bestPriceIndex = ILimitOrderQuoter(LIMIT_ORDER_QUOTER)
                ._findBestTokenToWethExecutionPrice(
                    executionPrices,
                    orders[i].buy
                );

            {
                ///@notice Pass the order, maxBeaconReward, and TokenToWethExecutionPrice into _executeTokenToWethSingle for execution.
                (
                    uint256 beaconReward,
                    uint256 conveyorReward
                ) = _executeTokenToWethOrder(
                        orders[i],
                        executionPrices[bestPriceIndex]
                    );
                ///@notice Increment the total beacon and conveyor reward.
                totalBeaconReward += beaconReward;
                totalConveyorReward += conveyorReward;
            }

            ///@notice Update the best execution price.
            executionPrices[bestPriceIndex] = ILimitOrderQuoter(
                LIMIT_ORDER_QUOTER
            ).simulateTokenToWethPriceChange(
                    uint128(orders[i].quantity),
                    executionPrices[bestPriceIndex]
                );

            unchecked {
                ++i;
            }
        }
        ///@notice Transfer the totalBeaconReward to the off chain executor.
        transferBeaconReward(totalBeaconReward, tx.origin, WETH);

        ///@notice Increment the conveyor balance.
        conveyorBalance += totalConveyorReward;

        return (totalBeaconReward, totalConveyorReward);
    }

    ///@notice Function to execute a single Token To Weth order.
    ///@param order - The order to be executed.
    ///@param executionPrice - The best priced TokenToWethExecutionPrice to execute the order on.
    function _executeTokenToWethOrder(
        OrderBook.LimitOrder memory order,
        SwapRouter.TokenToWethExecutionPrice memory executionPrice
    ) internal returns (uint256, uint256) {
        ///@notice Swap the batch amountIn on the batch lp address and send the weth back to the contract.
        (
            uint128 amountOutWeth,
            uint128 conveyorReward,
            uint128 beaconReward
        ) = _executeSwapTokenToWethOrder(
                executionPrice.lpAddressAToWeth,
                order
            );

        ///@notice Transfer the tokenOut amount to the order owner.
        transferTokensOutToOwner(order.owner, amountOutWeth, WETH);

        return (uint256(conveyorReward), uint256(beaconReward));
    }

    ///@notice Function to execute a swap from TokenToWeth for an order.
    ///@param lpAddressAToWeth - The best priced TokenToTokenExecutionPrice for the order to be executed on.
    ///@param order - The order to be executed.
    ///@return amountOutWeth - The amountOut in Weth after the swap.
    function _executeSwapTokenToWethOrder(
        address lpAddressAToWeth,
        OrderBook.LimitOrder memory order
    )
        internal
        returns (
            uint128 amountOutWeth,
            uint128 conveyorReward,
            uint128 beaconReward
        )
    {
        ///@notice Cache the order Quantity.
        uint256 orderQuantity = order.quantity;

        uint24 feeIn = order.feeIn;
        address tokenIn = order.tokenIn;

        ///@notice Calculate the amountOutMin for the tokenA to Weth swap.
        uint256 batchAmountOutMinAToWeth = ILimitOrderQuoter(LIMIT_ORDER_QUOTER)
            .calculateAmountOutMinAToWeth(
                lpAddressAToWeth,
                orderQuantity,
                order.taxIn,
                feeIn,
                tokenIn
            );

        ///@notice Swap from tokenA to Weth.
        amountOutWeth = uint128(
            swap(
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
        (conveyorReward, beaconReward) = ConveyorFeeMath.calculateReward(
            protocolFee,
            amountOutWeth
        );
        ///@notice If the order is a stoploss, and the beaconReward surpasses 0.05 WETH. Cap the protocol and the off chain executor at 0.05 WETH.
        if (order.stoploss) {
            if (STOP_LOSS_MAX_BEACON_REWARD < beaconReward) {
                beaconReward = STOP_LOSS_MAX_BEACON_REWARD;
                conveyorReward = STOP_LOSS_MAX_BEACON_REWARD;
            }
        }

        ///@notice Get the AmountIn for weth to tokenB.
        amountOutWeth = amountOutWeth - (beaconReward + conveyorReward);
    }

    ///@notice Function to execute an array of TokenToToken orders
    ///@param orders - Array of orders to be executed.
    function executeTokenToTokenOrders(OrderBook.LimitOrder[] memory orders)
        external
        onlyLimitOrderRouter
        returns (uint256, uint256)
    {
        TokenToTokenExecutionPrice[] memory executionPrices;
        address tokenIn = orders[0].tokenIn;

        uint24 feeIn = orders[0].feeIn;
        uint24 feeOut = orders[0].feeOut;

        {
            ///@notice Get all execution prices.
            ///@notice Get all prices for the pairing tokenIn to Weth
            (
                SpotReserve[] memory spotReserveAToWeth,
                address[] memory lpAddressesAToWeth
            ) = _getAllPrices(tokenIn, WETH, feeIn);

            ///@notice Get all prices for the pairing Weth to tokenOut
            (
                SpotReserve[] memory spotReserveWethToB,
                address[] memory lpAddressWethToB
            ) = _getAllPrices(WETH, orders[0].tokenOut, feeOut);

            executionPrices = ILimitOrderQuoter(LIMIT_ORDER_QUOTER)
                ._initializeTokenToTokenExecutionPrices(
                    tokenIn,
                    spotReserveAToWeth,
                    lpAddressesAToWeth,
                    spotReserveWethToB,
                    lpAddressWethToB
                );
        }

        ///@notice Set totalBeaconReward to 0
        uint256 totalBeaconReward = 0;
        ///@notice Set totalConveyorReward to 0
        uint256 totalConveyorReward = 0;

        ///@notice Loop through each Order.
        for (uint256 i = 0; i < orders.length; ) {
            ///@notice Create a variable to track the best execution price in the array of execution prices.
            uint256 bestPriceIndex = ILimitOrderQuoter(LIMIT_ORDER_QUOTER)
                ._findBestTokenToTokenExecutionPrice(
                    executionPrices,
                    orders[i].buy
                );

            {
                ///@notice Pass the order, maxBeaconReward, and TokenToWethExecutionPrice into _executeTokenToWethSingle for execution.
                (
                    uint256 beaconReward,
                    uint256 conveyorReward
                ) = _executeTokenToTokenOrder(
                        orders[i],
                        executionPrices[bestPriceIndex]
                    );
                totalBeaconReward += beaconReward;
                totalConveyorReward += conveyorReward;
            }

            ///@notice Update the best execution price.
            executionPrices[bestPriceIndex] = ILimitOrderQuoter(
                LIMIT_ORDER_QUOTER
            ).simulateTokenToTokenPriceChange(
                    uint128(orders[i].quantity),
                    executionPrices[bestPriceIndex]
                );

            unchecked {
                ++i;
            }
        }
        ///@notice Transfer the totalBeaconReward to the off chain executor.
        transferBeaconReward(totalBeaconReward, tx.origin, WETH);

        conveyorBalance += totalConveyorReward;

        return (totalBeaconReward, totalConveyorReward);
    }

    ///@notice Function to execute a single Token To Token order.
    ///@param order - The order to be executed.
    ///@param executionPrice - The best priced TokenToTokenExecution price to execute the order on.
    function _executeTokenToTokenOrder(
        OrderBook.LimitOrder memory order,
        TokenToTokenExecutionPrice memory executionPrice
    ) internal returns (uint256, uint256) {
        ///@notice Initialize variables to prevent stack too deep.
        uint256 amountInWethToB;
        uint128 conveyorReward;
        uint128 beaconReward;

        ///@notice Scope to prevent stack too deep.
        {
            ///@notice If the tokenIn is not weth.
            if (order.tokenIn != WETH) {
                ///@notice Execute the first swap from tokenIn to weth.
                (
                    amountInWethToB,
                    conveyorReward,
                    beaconReward
                ) = _executeSwapTokenToWethOrder(
                    executionPrice.lpAddressAToWeth,
                    order
                );

                if (amountInWethToB == 0) {
                    revert InsufficientOutputAmount();
                }
            } else {
                ///@notice Transfer the TokenIn to the contract.
                transferTokensToContract(order);

                ///@notice Cache the order quantity.
                uint256 amountIn = order.quantity;

                ///@notice Take out fees from the batch amountIn since token0 is weth.
                uint128 protocolFee = _calculateFee(
                    uint128(amountIn),
                    USDC,
                    WETH
                );

                ///@notice Calculate the conveyorReward and the off-chain logic executor reward.
                (conveyorReward, beaconReward) = ConveyorFeeMath
                    .calculateReward(protocolFee, uint128(amountIn));

                ///@notice If the order is a stoploss, and the beaconReward surpasses 0.05 WETH. Cap the protocol and the off chain executor at 0.05 WETH.
                if (order.stoploss) {
                    if (STOP_LOSS_MAX_BEACON_REWARD < beaconReward) {
                        beaconReward = STOP_LOSS_MAX_BEACON_REWARD;
                        conveyorReward = STOP_LOSS_MAX_BEACON_REWARD;
                    }
                }

                ///@notice Get the amountIn for the Weth to tokenB swap.
                amountInWethToB = amountIn - (beaconReward + conveyorReward);
            }
        }

        ///@notice Swap Weth for tokenB.
        uint256 amountOutInB = swap(
            WETH,
            order.tokenOut,
            executionPrice.lpAddressWethToB,
            order.feeOut,
            amountInWethToB,
            order.amountOutMin,
            order.owner,
            address(this)
        );

        if (amountOutInB == 0) {
            revert InsufficientOutputAmount();
        }

        return (uint256(conveyorReward), uint256(beaconReward));
    }

    ///@notice Transfer the order quantity to the contract.
    ///@param order - The orders tokens to be transferred.
    function transferTokensToContract(OrderBook.LimitOrder memory order) internal {
        IERC20(order.tokenIn).safeTransferFrom(
            order.owner,
            address(this),
            order.quantity
        );
    }

    //TODO: can we make the sandbox router address an immutable instead of a something that gets passed in?

    ///@notice Function to execute multicall orders from the context of LimitOrderExecutor.
    ///@param orders The orders to be executed.
    ///@param feeAmounts The calls to be executed.
    ///@param calls The feeAmounts to be removed from the input quantities.
    ///@param sandBoxRouter The address of the multicall contract.
    function executeMultiCallOrders(
        OrderBook.SandboxLimitOrder[] memory orders,
        uint128[] memory feeAmounts,
        SandboxRouter.SandboxMulticall memory calls,
        address sandBoxRouter
    ) external onlyLimitOrderRouter nonReentrant {
        ///@notice Create an array of swap tokens to be swapped out into weth. At max there will be orders.length
        address[] memory swapTokens = new address[](orders.length);
        ///@notice Iterate through each order and transfer the amountSpecifiedToFill to the multicall execution contract.
        for (uint256 i = 0; i < orders.length; ++i) {
            swapTokens[i] = orders[i].tokenIn;
            IERC20(orders[i].tokenIn).safeTransferFrom(
                orders[i].owner,
                address(sandBoxRouter),
                calls.amountSpecifiedToFill[i] - feeAmounts[i]
            );
            IERC20(orders[i].tokenIn).safeTransferFrom(
                orders[i].owner,
                address(this),
                feeAmounts[i]
            );
        }

        ///@notice Iterate through all the swapTokens and transfer the funds to the Conveyor Contract.
        {
            ///@notice Cache the balance prior to swapping the tokens.
            uint256 balanceBefore = IERC20(WETH).balanceOf(address(this));
            for (uint256 j = 0; j < swapTokens.length; ) {
                ///@notice Cache the contract balance on the swapToken.
                uint256 tokenBalance = IERC20(swapTokens[j]).balanceOf(
                    address(this)
                );
                ///@notice Only swap if we haven't swapped on this token already.
                if (tokenBalance > 0) {
                    ///@notice Only used for v3 since the tick upper/lower are derived in the swap logic.
                    uint256 amountOutMin = 0;
                    if (_lpIsNotUniV3(orders[j].quoteWethLiquidSwapPool)) {
                        ///@notice Get the reserves on the pool.
                        (uint128 r0, uint128 r1, ) = IUniswapV2Pair(
                            orders[j].quoteWethLiquidSwapPool
                        ).getReserves();
                        ///@notice If the swap is on v2 derive a proper amountOutMin.
                        amountOutMin = getAmountOut(
                            tokenBalance,
                            orders[j].tokenIn < WETH ? r0 : r1,
                            orders[j].tokenIn < WETH ? r1 : r0
                        );
                    }
                    ///@notice Swap all of orders fees on the current token.
                    swap(
                        swapTokens[j],
                        WETH,
                        orders[j].quoteWethLiquidSwapPool,
                        500,
                        tokenBalance,
                        amountOutMin,
                        address(this),
                        address(this)
                    );
                }
                unchecked {
                    ++j;
                }
            }
            ///@notice Increment the conveyor balance by the difference of its current balance and the balance prior to the swap.
            conveyorBalance +=
                IERC20(WETH).balanceOf(address(this)) -
                balanceBefore;
        }

        bool success;
        ///@notice Call the ChaosRouter to execute the calls.
        bytes memory bytesSig = abi.encodeWithSignature(
            "executeMultiCallCallback(MultiCall)",
            calls
        );

        assembly {
            mstore(0x00, bytesSig)

            success := call(
                gas(), // gas remaining
                sandBoxRouter, // destination address
                0, // no ether
                0x00, // input buffer (starts after the first 32 bytes in the `data` array)
                0x04, // input length (loaded from the first 32 bytes in the `data` array)
                0x00, // output buffer
                0x00 // output length
            )
        }

        require(success);
    }

    ///@notice Function to withdraw owner fee's accumulated
    function withdrawConveyorFees() external {
        if (reentrancyStatus == true) {
            revert Reentrancy();
        }
        reentrancyStatus = true;

        ///@notice Revert if caller is not the owner.
        if (msg.sender != owner) {
            revert MsgSenderIsNotOwner();
        }

        ///@notice Unwrap the the conveyorBalance.
        IWETH(WETH).withdraw(conveyorBalance);

        safeTransferETH(owner, conveyorBalance);
        ///@notice Set the conveyorBalance to 0 prior to transferring the ETH.
        conveyorBalance = 0;

        ///@notice Set the reentrancy status to false after the conveyorBalance has been decremented to prevent reentrancy.
        reentrancyStatus = false;
    }

    ///@notice Function to confirm ownership transfer of the contract.
    function confirmTransferOwnership() external {
        if (msg.sender != tempOwner) {
            revert UnauthorizedCaller();
        }
        ///@notice Cleanup tempOwner storage.
        tempOwner = address(0);
        owner = msg.sender;
    }

    ///@notice Function to transfer ownership of the contract.
    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) {
            revert UnauthorizedCaller();
        }

        if (newOwner == address(0)) {
            revert InvalidAddress();
        }
        tempOwner = newOwner;
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
}
