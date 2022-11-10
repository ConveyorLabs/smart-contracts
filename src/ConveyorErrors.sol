// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

//TODO: decide if we should add things like order ids and values into the errors
error InsufficientGasCreditBalance();
error InsufficientGasCreditBalanceForOrderExecution();
error InsufficientWalletBalance();
error OrderDoesNotExist(bytes32 orderId);
error OrderHasInsufficientSlippage(bytes32 orderId);
error SwapFailed(bytes32 orderId);
error OrderDoesNotMeetExecutionPrice(bytes32 orderId);
error TokenTransferFailed(bytes32 orderId);
error IncongruentTokenInOrderGroup();
error OrderNotRefreshable();
error OrderHasReachedExpiration();
error InsufficientOutputAmount();
error InsufficientInputAmount();
error InsufficientLiquidity();
error InsufficientDepositAmount();
error InsufficientAllowanceForOrderPlacement();
error InvalidBatchOrder();
error IncongruentInputTokenInBatch();
error IncongruentOutputTokenInBatch();
error IncongruentFeeInInBatch();
error IncongruentFeeOutInBatch();
error IncongruentTaxedTokenInBatch();
error NonEOAStoplossExecution();
error IncongruentStoplossStatus();
error IncongruentBuySellStatusInBatch();
error WethWithdrawUnsuccessful();
error MsgSenderIsNotTxOrigin();
error MsgSenderIsNotLimitOrderRouter();
error MsgSenderIsNotLimitOrderExecutor();
error MsgSenderIsNotSandboxRouter();
error MsgSenderIsNotOwner();
error Reentrancy();
error ETHTransferFailed();
error InvalidTokenPairIdenticalAddress();
error InvalidTokenPair();
error InvalidAddress();
error UnauthorizedCaller();
error UnauthorizedUniswapV3CallbackCaller();
error InvalidOrderUpdate();
error DuplicateOrdersInExecution();
error VerifierDilemmaGasPrice();
error InvalidCalldata();
error InsufficientMsgValue();
error InsufficientAllowanceForOrderUpdate();
error InsufficientLiquidityForDynamicFee();
error SandboxCallFailed();
error InvalidTransferAddressArray();
error AddressIsZero();
error IdenticalTokenAddresses();
error InvalidInputTokenForOrderPlacement();
error SandboxFillAmountNotSatisfied(
    bytes32 orderId,
    uint256 amountFilled,
    uint256 fillAmountRequired
);

error SandboxAmountOutRequiredNotSatisfied(
    bytes32 orderId,
    uint256 amountOut,
    uint256 amountOutRequired
);

error FillAmountSpecifiedGreaterThanAmountRemaining(
    uint256 fillAmountSpecified,
    uint256 amountInRemaining,
    bytes32 orderId
);
error ConveyorFeesNotPaid(
    uint256 expectedFees,
    uint256 feesPaid,
    uint256 unpaidFeesRemaining
);
