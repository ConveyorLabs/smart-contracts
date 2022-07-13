// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.15;

error InsufficientGasCreditBalance();
error InsufficientGasCreditBalanceForOrderExecution();
error InsufficientWalletBalance();
error OrderDoesNotExist(bytes32 orderId);
error IncongruentTokenInOrderGroup();
error OrderNotRefreshable();
error OrderHasReachedExpiration();
error InsufficientOutputAmount();
error MsgSenderIsNotOwner();
error InsufficientDepositAmount();
error InvalidBatchOrder();
error IncongruentInputTokenInBatch();
error IncongruentOutputTokenInBatch();
error IncongruentTaxedTokenInBatch();
error IncongruentBuySellStatusInBatch();
error WethWithdrawUnsuccessful();
