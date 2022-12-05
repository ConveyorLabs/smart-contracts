// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

error InsufficientWalletBalance(
    address account,
    uint256 balance,
    uint256 balanceNeeded
);
error OrderDoesNotExist(bytes32 orderId);
error OrderQuantityIsZero();
error InsufficientOrderInputValue();
error IncongruentInputTokenInOrderGroup(address token, address expectedToken);
error TokenInIsTokenOut();
error IncongruentOutputTokenInOrderGroup(address token, address expectedToken);
error InsufficientOutputAmount(uint256 amountOut, uint256 expectedAmountOut);
error InsufficientInputAmount(uint256 amountIn, uint256 expectedAmountIn);
error InsufficientLiquidity();
error InsufficientAllowanceForOrderPlacement(
    address token,
    uint256 approvedQuantity,
    uint256 approvedQuantityNeeded
);
error InsufficientAllowanceForOrderUpdate(
    address token,
    uint256 approvedQuantity,
    uint256 approvedQuantityNeeded
);
error InvalidOrderGroupSequence();
error IncongruentFeeInInOrderGroup();
error IncongruentFeeOutInOrderGroup();
error IncongruentTaxedTokenInOrderGroup();
error IncongruentStoplossStatusInOrderGroup();
error IncongruentBuySellStatusInOrderGroup();
error NonEOAStoplossExecution();
error MsgSenderIsNotTxOrigin();
error MsgSenderIsNotLimitOrderRouter();
error MsgSenderIsNotLimitOrderExecutor();
error MsgSenderIsNotOwner();
error MsgSenderIsNotOrderOwner();
error MsgSenderIsNotOrderBook();
error MsgSenderIsNotTempOwner();
error Reentrancy();
error ETHTransferFailed();
error InvalidAddress();
error UnauthorizedUniswapV3CallbackCaller();
error DuplicateOrderIdsInOrderGroup();
error InvalidCalldata();
error InsufficientMsgValue();
error UnauthorizedCaller();
error AmountInIsZero();
error AddressIsZero();
error IdenticalTokenAddresses();
error InvalidInputTokenForOrderPlacement();
error OrderNotEligibleForRefresh(bytes32 orderId);
error ConveyorFeesNotPaid(
    uint256 expectedFees,
    uint256 feesPaid,
    uint256 unpaidFeesRemaining
);
error InsufficientExecutionCredit(uint256 msgValue, uint256 minExecutionCredit);
error WithdrawAmountExceedsExecutionCredit(
    uint256 amount,
    uint256 executionCredit
);
error MsgValueIsNotCumulativeExecutionCredit(
    uint256 msgValue,
    uint256 cumulativeExecutionCredit
);
