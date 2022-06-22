// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.14;

contract ConveyorErrors {
    error InsufficientGasCreditBalance();
    error InsufficientGasCreditBalanceForOrderExecution();
    error InsufficientWalletBalance();

    error OrderDoesNotExist(bytes32 orderId);
    error IncongruentTokenInOrderGroup();

    error InsufficientOutputAmount();
}
