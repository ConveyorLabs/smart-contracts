// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "./utils/Swap.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "./utils/ScriptRunner.sol";
import "../LimitOrderRouter.sol";
import "../LimitOrderQuoter.sol";
import "../LimitOrderExecutor.sol";
import "../interfaces/ILimitOrderRouter.sol";
import "../interfaces/IOrderBook.sol";
import "../interfaces/ISandboxRouter.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;
}

contract SandboxRouterTest is DSTest {
    //Initialize All contract and Interface instances
    ILimitOrderRouter limitOrderRouter;
    IOrderBook orderBook;
    LimitOrderExecutorWrapper limitOrderExecutor;
    LimitOrderQuoter limitOrderQuoter;
    ISandboxRouter sandboxRouter;
    ScriptRunner scriptRunner;

    Swap swapHelper;
    Swap swapHelperUniV2;

    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ///@notice Initialize cheatcodes
    CheatCodes cheatCodes;

    ///@notice Test Token Address's
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address LINK = 0x218532a12a389a4a92fC0C5Fb22901D1c19198aA;
    address UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    
    ///@notice Factory and router address's
    address _sushiSwapRouterAddress =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    // address _sushiFactoryAddress = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;


    ///@notice Uniswap v2 Deployment bytescode
    bytes32 _uniswapV2HexDem =
        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";

    ///@notice Initialize array of Dex specifications
    bytes32[] _hexDems = [_uniswapV2HexDem, _uniswapV2HexDem];
    address[] _dexFactories = [_uniV2FactoryAddress, _uniV3FactoryAddress];
    bool[] _isUniV2 = [true, false];

    ///@notice Fast Gwei Aggregator V3 address
    address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    function setUp() public {
        scriptRunner = new ScriptRunner();
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        swapHelper = new Swap(_sushiSwapRouterAddress, WETH);
        swapHelperUniV2 = new Swap(uniV2Addr, WETH);

        limitOrderQuoter = new LimitOrderQuoter(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        );

        limitOrderExecutor = new LimitOrderExecutorWrapper(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            address(limitOrderQuoter),
            _hexDems,
            _dexFactories,
            _isUniV2,
            aggregatorV3Address
        );

        limitOrderRouter = ILimitOrderRouter(
            limitOrderExecutor.LIMIT_ORDER_ROUTER()
        );

        ///@notice Initialize an instance of the SandboxRouter Interface
        sandboxRouter= ISandboxRouter(limitOrderRouter.getSandboxRouterAddress());
    }

    ///@notice ExecuteMulticallOrder Sandbox Router test
    function testExecuteMulticallOrderSingleV2() public {
        ///@notice Deal funds to all of the necessary receivers
        cheatCodes.deal(address(this), type(uint128).max);
        cheatCodes.deal(address(swapHelper), type(uint256).max);
        ///@notice Deposit Gas Credits to cover order execution.
        depositGasCreditsForMockOrders(type(uint128).max);
        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);
        
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order = newMockSandboxOrder(false, 10000000000000000000, 1, DAI, WETH);

         ///@notice Deal some ETH to compensate the fee
        cheatCodes.deal(address(sandboxRouter), type(uint128).max);
        cheatCodes.prank(address(sandboxRouter));
        ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: 500000 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");
        ///@notice Initialize Arrays for Multicall struct. 
        bytes32[] memory orderIds = new bytes32[](1);
        address[] memory transferAddress = new address[](1);
        uint128[] memory fillAmounts = new uint128[](1);
        SandboxRouter.Call[] memory calls = new SandboxRouter.Call[](2);

        {
            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
            ///@notice Place the Order. 
            orderIds[0]=placeMockOrder(order);
            ///@notice Grab the order fee
            uint256 cumulativeFee = limitOrderRouter.getSandboxLimitOrderById(orderIds[0]).fee;
            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0]=daiWethV2;
            ///@notice Set the fill amount to the total amountIn on the order i.e. 1000 DAI.
            fillAmounts[0]= order.amountInRemaining;
            ///@notice Create a single v2 swap call for the multicall. 
            calls[0]= newUniV2Call(daiWethV2, 0, 100, address(this));
            ///@notice Create a call to compensate the feeAmount
            calls[1]= feeCompensationCall(cumulativeFee);
        }

        ///@notice Create a new SandboxMulticall
        SandboxRouter.SandboxMulticall memory multiCall = newMockMulticall(orderIds, fillAmounts, transferAddress, calls);
        
         ///@notice Prank tx.origin to mock an external executor
        cheatCodes.prank(tx.origin);

        ///@notice Execute the SandboxMulticall on the sandboxRouter
        sandboxRouter.executeSandboxMulticall(multiCall);
    }

    ///@notice ExecuteMulticallOrder Sandbox Router test
    function testExecuteMulticallOrderSingleV3() public {
        ///@notice Deal funds to all of the necessary receivers
        cheatCodes.deal(address(this), type(uint128).max);
        cheatCodes.deal(address(swapHelper), type(uint256).max);
        ///@notice Deposit Gas Credits to cover order execution.
        depositGasCreditsForMockOrders(type(uint128).max);
        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);
        // IERC20(DAI).approve(address(sandboxRouter), type(uint256).max);
        ///@notice Deal some ETH to compensate the fee
        cheatCodes.deal(address(sandboxRouter), type(uint128).max);
        cheatCodes.prank(address(sandboxRouter));
        ///@notice Wrap the weth to send to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: 500000 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order = newMockSandboxOrder(false, 100000000000000000000, 1, DAI, WETH);
        
        ///@notice Initialize Arrays for Multicall struct. 
        bytes32[] memory orderIds = new bytes32[](1);
        address[] memory transferAddress = new address[](1);
        uint128[] memory fillAmounts = new uint128[](1);
        SandboxRouter.Call[] memory calls = new SandboxRouter.Call[](2);

        {
            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV3 = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
            ///@notice Place the Order. 
            orderIds[0]=placeMockOrder(order);
            ///@notice Grab the order fee
            uint256 cumulativeFee = limitOrderRouter.getSandboxLimitOrderById(orderIds[0]).fee;
            console.log(cumulativeFee);
            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0]=address(sandboxRouter);
            ///@notice Set the fill amount to the total amountIn on the order i.e. 1000 DAI.
            fillAmounts[0]= order.amountInRemaining;
            ///@notice Create a single v2 swap call for the multicall. 
            calls[0]= newUniV3Call(daiWethV3, address(sandboxRouter), address(this), true, 100000000000000000000, DAI);
            ///@notice Create a call to compensate the feeAmount
            calls[1]= feeCompensationCall(cumulativeFee);

        }

        ///@notice Create a new SandboxMulticall
        SandboxRouter.SandboxMulticall memory multiCall = newMockMulticall(orderIds, fillAmounts, transferAddress, calls);
        
         ///@notice Prank tx.origin to mock an external executor
        cheatCodes.prank(tx.origin);
        
        ///@notice Execute the SandboxMulticall on the sandboxRouter
        sandboxRouter.executeSandboxMulticall(multiCall);
    }

    

    ///@notice Helper function to create call to compensate the fees during execution
    function feeCompensationCall(uint256 cumulativeFee) public view returns (SandboxRouter.Call memory){
        bytes memory callData= abi.encodeWithSignature("transfer(address,uint256)", address(limitOrderExecutor), cumulativeFee);
        return SandboxRouter.Call({
            target: WETH,
            callData:callData
        });
    }

    ///@notice Helper function to create a single mock call for a v2 swap. 
    function newUniV2Call(address _lp, uint256 amount0Out, uint256 amount1Out, address _receiver) public pure returns (SandboxRouter.Call memory) {
        bytes memory callData = abi.encodeWithSignature("swap(uint256,uint256,address,bytes)", amount0Out, amount1Out, _receiver, new bytes(0));
        return SandboxRouter.Call({
            target:_lp,
            callData:callData
        });
    }

    ///@notice Helper function to create a single mock call for a v3 swap. 
    function newUniV3Call(address _lp,  address _sender, address _receiver, bool _zeroForOne, uint256 _amountIn, address _tokenIn) public pure returns (SandboxRouter.Call memory){
        ///@notice Pack the required data for the call.
        bytes memory data = abi.encode(_zeroForOne, _tokenIn, _sender);
        ///@notice Encode the callData for the call. 
        bytes memory callData = abi.encodeWithSignature("swap(address,bool,int256,uint160,bytes)", _receiver, _zeroForOne, int256(_amountIn), _zeroForOne ? TickMath.MIN_SQRT_RATIO +1 : TickMath.MAX_SQRT_RATIO -1,data);
        ///@notice Return the call
        return SandboxRouter.Call({
            target:_lp,
            callData:callData
        });
    }

    ///@notice Helper function to create a Sandox Multicall 
    function newMockMulticall(bytes32[] memory orderId, uint128[] memory fillAmounts, address[] memory transferAddresses, SandboxRouter.Call[] memory _calls) public pure returns (SandboxRouter.SandboxMulticall memory) {
        return SandboxRouter.SandboxMulticall({
            orderIds:orderId,
            fillAmount:fillAmounts,
            transferAddress:transferAddresses,
            calls:_calls
        });
    }



    ///@notice Helper function to initialize a mock sandbox limit order
    function newMockSandboxOrder(
        bool buy,
        uint128 amountInRemaining,
        uint128 amountOutRemaining,
        address tokenIn,
        address tokenOut
    ) internal view returns (OrderBook.SandboxLimitOrder memory order) {
        //Initialize mock order
        order = OrderBook.SandboxLimitOrder({
            buy: buy,
            amountOutRemaining: amountOutRemaining,
            amountInRemaining: amountInRemaining,
            lastRefreshTimestamp: 0,
            expirationTimestamp: type(uint32).max,
            fee: 0,
            owner: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            orderId: bytes32(0)
        });
    }

    ///@notice Gas credit deposit helper function.
    function depositGasCreditsForMockOrders(uint256 _amount) public {
        (bool depositSuccess, ) = address(limitOrderRouter).call{
            value: _amount
        }(abi.encodeWithSignature("depositGasCredits()"));

        require(depositSuccess, "error when depositing gas credits");
    }

    ///@notice Helper function to place a single sandbox limit order
    function placeMockOrder(OrderBook.SandboxLimitOrder memory order)
        internal
        returns (bytes32 orderId)
    {
        //create a new array of orders
        OrderBook.SandboxLimitOrder[] memory orderGroup = new OrderBook.SandboxLimitOrder[](
            1
        );
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        bytes32[] memory orderIds = limitOrderRouter.placeSandboxLimitOrder(orderGroup);

        orderId = orderIds[0];
    }

    ///@notice helper function to place multiple sandbox orders
    function placeMultipleMockOrder(OrderBook.SandboxLimitOrder[] memory orderGroup)
        internal
        returns (bytes32[] memory)
    {
        //place order
        bytes32[] memory orderIds = orderBook.placeSandboxLimitOrder(orderGroup);

        return orderIds;
    }

}


//wrapper around SwapRouter to expose internal functions for testing
contract LimitOrderExecutorWrapper is LimitOrderExecutor {
    constructor(
        address _weth,
        address _usdc,
        address _limitOrderQuoter,
        bytes32[] memory _initBytecodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2,
        address _gasOracle
    )
        LimitOrderExecutor(
            _weth,
            _usdc,
            _limitOrderQuoter,
            _initBytecodes,
            _dexFactories,
            _isUniV2,
            _gasOracle
        )
    {}

    function getV3PoolFee(address pairAddress)
        public
        view
        returns (uint24 poolFee)
    {
        return getV3PoolFee(pairAddress);
    }

    function lpIsNotUniV3(address lp) public returns (bool) {
        return _lpIsNotUniV3(lp);
    }

    // receive() external payable {}

    function swapV2(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _reciever,
        address _sender
    ) public returns (uint256) {
        return
            _swapV2(
                _tokenIn,
                _tokenOut,
                _lp,
                _amountIn,
                _amountOutMin,
                _reciever,
                _sender
            );
    }

    function swapV3(
        address _lp,
        address _tokenIn,
        address _tokenOut,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _reciever,
        address _sender
    ) public returns (uint256) {
        return
            _swapV3(
                _lp,
                _tokenIn,
                _tokenOut,
                _fee,
                _amountIn,
                _amountOutMin,
                _reciever,
                _sender
            );
    }

    function getAllPrices(
        address token0,
        address token1,
        uint24 FEE
    ) public view returns (SpotReserve[] memory prices, address[] memory lps) {
        return _getAllPrices(token0, token1, FEE);
    }

    function calculateV2SpotPrice(
        address token0,
        address token1,
        address _factory,
        bytes32 _initBytecode
    ) public view returns (SpotReserve memory spRes, address poolAddress) {
        return _calculateV2SpotPrice(token0, token1, _factory, _initBytecode);
    }

    function calculateV3SpotPrice(
        address token0,
        address token1,
        uint24 FEE,
        address _factory
    ) public returns (SpotReserve memory, address) {
        return _calculateV3SpotPrice(token0, token1, FEE, _factory);
    }

    function calculateFee(
        uint128 amountIn,
        address usdc,
        address weth
    ) public view returns (uint128) {
        return _calculateFee(amountIn, usdc, weth);
    }

    function _swap(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _reciever,
        address _sender
    ) public returns (uint256 amountReceived) {
        return
            swap(
                _tokenIn,
                _tokenOut,
                _lp,
                _fee,
                _amountIn,
                _amountOutMin,
                _reciever,
                _sender
            );
    }
}
