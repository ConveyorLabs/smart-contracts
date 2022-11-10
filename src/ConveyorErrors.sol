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

error IncongruentTokenInOrderGroup(address token, address expectedToken);

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
