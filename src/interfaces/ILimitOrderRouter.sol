// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface ILimitOrderRouter {
    function gasCreditBalance(address addr) external returns (uint256);

    function depositGasCredits() external payable returns (bool success);

    function withdrawGasCredits(uint256 value) external returns (bool success);

    function refreshOrder(bytes32[] memory orderIds) external;

    function validateAndCancelOrder(bytes32 orderId)
        external
        returns (bool success);

    function executeOrders(bytes32[] calldata orderIds) external;

    function confirmTransferOwnership() external;

    function transferOwnership(address newOwner) external;
    function getGasPrice() external view returns (uint256);
   
}
