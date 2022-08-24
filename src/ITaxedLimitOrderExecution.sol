import "./OrderBook.sol";
interface ITaxedLimitOrderExecution {
    
    function executeTokenToTokenTaxedOrders(OrderBook.Order[] memory orders) external;
    function executeTokenToWethTaxedOrders(OrderBook.Order[] memory orders) external;
}