// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

error InsufficientGasCreditBalance(
    address account,
    uint256 gasCreditBalance,
    uint256 gasCreditBalanceNeeded
);
error InsufficientWalletBalance(
    address account,
    uint256 balance,
    uint256 balanceNeeded
);
error OrderDoesNotExist(bytes32 orderId);
error IncongruentInputTokenInOrderGroup(address token, address expectedToken);
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
error MsgSenderIsNotSandboxRouter();
error MsgSenderIsNotOwner();
error MsgSenderIsNotTempOwner();
error Reentrancy();
error ETHTransferFailed();
error InvalidAddress();
error UnauthorizedUniswapV3CallbackCaller();
error DuplicateOrderIdsInOrderGroup();
error InvalidCalldata();
error InsufficientMsgValue();
error UnauthorizedCaller();

///@notice Returns the index of the call that failed within the SandboxRouter.Call[] array
error SandboxCallFailed(uint256 callIndex);
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
