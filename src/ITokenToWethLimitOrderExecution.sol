import "./OrderBook.sol";

interface ITokenToWethLimitOrderExecution {
    function executeTokenToWethOrderSingle(OrderBook.Order[] memory orders) external;
    function executeTokenToWethOrders(OrderBook.Order[] memory orders) external;

}