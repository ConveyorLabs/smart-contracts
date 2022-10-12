import "../OrderBook.sol";

interface ILimitOrderExecutor {
    function executeTokenToWethOrders(OrderBook.Order[] memory orders)
        external
        returns (uint256, uint256);

    function executeTokenToTokenOrders(OrderBook.Order[] memory orders)
        external
        returns (uint256, uint256);
}