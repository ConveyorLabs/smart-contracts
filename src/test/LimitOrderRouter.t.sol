// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "./utils/Swap.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "./utils/ScriptRunner.sol";
import "../OrderBook.sol";
import "../LimitOrderRouter.sol";
import "../LimitOrderBatcher.sol";
import "../TokenToTokenLimitOrderExecution.sol";
import "../TokenToWethLimitOrderExecution.sol";
import "../TaxedTokenLimitOrderExecution.sol";

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

contract LimitOrderRouterTest is DSTest {
    //Initialize limit-v0 contract for testing
    LimitOrderRouterWrapper limitOrderRouter;
    LimitOrderBatcher limitOrderBatcher;
    //Initialize execution contracts
    TokenToTokenLimitOrderExecution tokenToTokenExecution;
    TaxedTokenLimitOrderExecution taxedTokenExecution;
    TokenToWethLimitOrderExecution tokenToWethExecution;

    OrderRouter orderRouter;
    //Initialize OrderBook
    OrderBook orderBook;

    ScriptRunner scriptRunner;

    Swap swapHelper;
    Swap swapHelperUniV2;

    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    //Initialize cheatcodes
    CheatCodes cheatCodes;

    //Test Token Address's
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address LINK = 0x218532a12a389a4a92fC0C5Fb22901D1c19198aA;
    address UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address TAXED_TOKEN = 0xE7eaec9Bca79d537539C00C58Ae93117fB7280b9; //
    address TAXED_TOKEN_1 = 0xe0a189C975e4928222978A74517442239a0b86ff; //
    address TAXED_TOKEN_2 = 0xd99793A840cB0606456916d1CF5eA199ED93Bf97; //6% tax CHAOS token 27
    address TAXED_TOKEN_3 = 0xcFEB09C3c5F0f78aD72166D55f9e6E9A60e96eEC;

    //MAX_UINT for testing
    uint256 constant MAX_UINT = 2**256 - 1;

    uint32 constant MAX_U32 = 2**32 - 1;

    //Factory and router address's
    address _sushiSwapRouterAddress =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    // address _sushiFactoryAddress = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    //Chainlink ERC20 address
    address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    // bytes32 _sushiHexDem =
    //     hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303";
    bytes32 _uniswapV2HexDem =
        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";

    //Initialize array of Dex specifications
    bytes32[] _hexDems = [
        _uniswapV2HexDem,
        // _sushiHexDem,
        bytes32(0)
    ];
    address[] _dexFactories = [
        _uniV2FactoryAddress,
        // _sushiFactoryAddress,
        _uniV3FactoryAddress
    ];
    bool[] _isUniV2 = [
        true,
        //  true,
        false
    ];

    uint256 alphaXDivergenceThreshold = 3402823669209385000000000000000000; //0.00001
    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    function setUp() public {
        scriptRunner = new ScriptRunner();
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        swapHelper = new Swap(_sushiSwapRouterAddress, WETH);
        swapHelperUniV2 = new Swap(uniV2Addr, WETH);

        //Initialize swap router in constructor
        orderRouter = new OrderRouter(
            _hexDems,
            _dexFactories,
            _isUniV2,
            alphaXDivergenceThreshold
        );

        limitOrderBatcher = new LimitOrderBatcher(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6,
            address(orderRouter)
        );

        tokenToTokenExecution = new TokenToTokenLimitOrderExecution(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6,
            address(orderRouter)
        );

        taxedTokenExecution = new TaxedTokenLimitOrderExecution(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6,
            address(orderRouter)
        );

        tokenToWethExecution = new TokenToWethLimitOrderExecution(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6,
            address(orderRouter)
        );

        limitOrderRouter = new LimitOrderRouterWrapper(
            0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            3000000,
            address(tokenToTokenExecution),
            address(taxedTokenExecution),
            address(tokenToWethExecution),
            address(orderRouter)
        );
        console.log(address(limitOrderRouter));
    }

    function testOnlyEOA() public {
        cheatCodes.prank(tx.origin);
        limitOrderRouter.invokeOnlyEOA();
    }

    function testFailOnlyEOA() public {
        limitOrderRouter.invokeOnlyEOA();
    }

    //================================================================
    //================= Validate Order Sequence Tests ================
    //================================================================

    function testValidateOrderSequence() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);

        cheatCodes.deal(address(swapHelper), MAX_UINT);

        OrderBook.Order[] memory orderBatch = newMockTokenToTokenBatch();

        limitOrderRouter.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_InvalidBatchOrder() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        OrderBook.Order[]
            memory orderBatch = newMockTokenToWethBatch_InvalidBatchOrdering();

        limitOrderRouter.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentInputTokenInBatch()
        public
    {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        OrderBook.Order[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentTokenIn();

        limitOrderRouter.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentTokenOut() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        OrderBook.Order[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentTokenOut();
        limitOrderRouter.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentBuySellStatusInBatch()
        public
    {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        OrderBook.Order[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentBuySellStatus();
        limitOrderRouter.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentTaxedTokenInBatch()
        public
    {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        OrderBook.Order[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentTaxedTokenInBatch();
        limitOrderRouter.validateOrderSequencing(orderBatch);
    }

    //================================================================
    //==================== Execution Tests ===========================
    //================================================================

    ///@notice Test to Execute a batch of Token To Weth Orders
    function testExecuteTokenToWethOrderBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        IERC20(DAI).approve(address(orderRouter), MAX_UINT);
        bytes32[] memory tokenToWethOrderBatch = placeNewMockTokenToWethBatch();

        //check that the orders have been placed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            OrderBook.Order memory order = limitOrderRouter.getOrderById(
                tokenToWethOrderBatch[i]
            );

            assert(order.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeOrders(tokenToWethOrderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            OrderBook.Order memory order = limitOrderRouter.getOrderById(
                tokenToWethOrderBatch[i]
            );
            assert(order.orderId == bytes32(0));
        }
    }

    ///@notice Test to execute a single token to with order
    function testExecuteWethToTokenSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        cheatCodes.deal(address(this), MAX_UINT);

        (bool depositSuccess, ) = address(WETH).call{value: 500000000000 ether}(
            abi.encodeWithSignature("deposit()")
        );

        require(depositSuccess, "failure when depositing ether into weth");

        IERC20(WETH).approve(address(orderRouter), MAX_UINT);
        //Create a new mock order
        OrderBook.Order memory order = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );

        bytes32 orderId = placeMockOrder(order);
        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = orderId;
        //check that the orders have been placed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );

            assert(order0.orderId != bytes32(0));
        }
        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );
            assert(order0.orderId == bytes32(0));
        }
    }

    ///@notice Teas To execute a single token to Weth order Dai/Weth
    function testExecuteTokenToWethSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        IERC20(DAI).approve(address(orderRouter), MAX_UINT);
        //Create a new mock order
        OrderBook.Order memory order = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        bytes32 orderId = placeMockOrder(order);

        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = orderId;
        //check that the orders have been placed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );

            assert(order0.orderId != bytes32(0));
        }
        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );
            assert(order0.orderId == bytes32(0));
        }
    }

    ///@notice Test to execute a batch of Weth to Token orders Weth/Dai
    function testExecuteWethToTokenOrderBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        cheatCodes.deal(address(this), MAX_UINT);

        //Deposit weth to address(this)
        (bool depositSuccess, ) = address(WETH).call{value: 500000000000 ether}(
            abi.encodeWithSignature("deposit()")
        );

        //require that the deposit was a success
        require(depositSuccess, "testDepositGasCredits: deposit failed");

        IERC20(WETH).approve(address(orderRouter), MAX_UINT);

        bytes32[] memory tokenToWethOrderBatch = placeNewMockWethToTokenBatch();
        //Make sure the orders have been placed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                tokenToWethOrderBatch[i]
            );

            assert(order0.orderId != bytes32(0));
        }
        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeOrders(tokenToWethOrderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                tokenToWethOrderBatch[i]
            );
            assert(order0.orderId == bytes32(0));
        }
    }

    ///@notice Test to execute a single token to token order. Dai/Uni
    function testExecuteTokenToTokenSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        IERC20(DAI).approve(address(orderRouter), MAX_UINT);
        OrderBook.Order memory order = newMockOrder(
            DAI,
            UNI,
            1,
            false,
            false,
            0,
            1,
            500000000000000000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        bytes32 orderId = placeMockOrder(order);

        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = orderId;
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );

            assert(order0.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );
            assert(order0.orderId == bytes32(0));
        }
    }

    ///@notice Test To Execute a batch of Token to token orders Usdc/Uni
    function testExecuteTokenToTokenBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        IERC20(USDC).approve(address(orderRouter), MAX_UINT);

        bytes32[]
            memory tokenToTokenOrderBatch = placeNewMockTokenToTokenBatch();

        //check that the orders have been placed
        for (uint256 i = 0; i < tokenToTokenOrderBatch.length; ++i) {
            OrderBook.Order memory order = limitOrderRouter.getOrderById(
                tokenToTokenOrderBatch[i]
            );

            assert(order.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeOrders(tokenToTokenOrderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < tokenToTokenOrderBatch.length; ++i) {
            OrderBook.Order memory order = limitOrderRouter.getOrderById(
                tokenToTokenOrderBatch[i]
            );
            assert(order.orderId == bytes32(0));
        }
    }

    ///@notice Test to execute a single weth to taxed order
    function testExecuteWethToTaxedTokenSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        cheatCodes.deal(address(this), MAX_UINT);

        (bool depositSuccess, ) = address(WETH).call{value: 500000000000 ether}(
            abi.encodeWithSignature("deposit()")
        );

        require(depositSuccess, "failure when depositing ether into weth");

        IERC20(WETH).approve(address(orderRouter), MAX_UINT);
        OrderBook.Order memory order = newMockOrder(
            WETH,
            TAXED_TOKEN,
            1,
            false,
            true,
            0,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );

        bytes32 orderId = placeMockOrder(order);

        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = orderId;

        //check that the orders have been placed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order1 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );

            assert(order1.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order1 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );
            assert(order1.orderId == bytes32(0));
        }
    }

    ///@notice Test to execute a batch of weth to taxed token orders
    function testExecuteWethToTaxedTokenBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        cheatCodes.deal(address(this), MAX_UINT);

        (bool depositSuccess, ) = address(WETH).call{value: 500000000000 ether}(
            abi.encodeWithSignature("deposit()")
        );

        require(depositSuccess, "failure when depositing ether into weth");

        IERC20(WETH).approve(address(orderRouter), MAX_UINT);

        bytes32[] memory wethToTaxedOrderBatch = placeNewMockWethToTaxedBatch();

        //check that the orders have been placed
        for (uint256 i = 0; i < wethToTaxedOrderBatch.length; ++i) {
            OrderBook.Order memory order = limitOrderRouter.getOrderById(
                wethToTaxedOrderBatch[i]
            );

            assert(order.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeOrders(wethToTaxedOrderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < wethToTaxedOrderBatch.length; ++i) {
            OrderBook.Order memory order = limitOrderRouter.getOrderById(
                wethToTaxedOrderBatch[i]
            );
            assert(order.orderId == bytes32(0));
        }
    }

    ///@notice Test to execute a single taxed to token order Taxed_token/Weth
    function testExecuteTaxedTokenToWethSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);

        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(orderRouter), MAX_UINT);

        OrderBook.Order memory order = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order[] memory orderGroup = new OrderBook.Order[](1);
        orderGroup[0] = order;
        bytes32[] memory orderBatch = limitOrderRouter.placeOrder(orderGroup);
        //Ensure all of the orders have been placed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );

            assert(order0.orderId != bytes32(0));
        }
        //Prank tx.origin since executeOrders is onlyEOA
        cheatCodes.prank(tx.origin);
        //Execute the batch
        limitOrderRouter.executeOrders(orderBatch);

        //Ensure the batch has been fulfilled
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );
            assert(order0.orderId == bytes32(0));
        }
    }

    ///@notice Test to execute a batch of Taxed to token orders
    function testExecuteTaxedTokenToWethBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        IERC20(TAXED_TOKEN).approve(address(orderRouter), MAX_UINT);

        bytes32[]
            memory tokenToWethOrderBatch = placeNewMockTokenToWethTaxedBatch();

        //check that the orders have been placed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            OrderBook.Order memory order = limitOrderRouter.getOrderById(
                tokenToWethOrderBatch[i]
            );

            assert(order.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        //Execute the orders
        limitOrderRouter.executeOrders(tokenToWethOrderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            OrderBook.Order memory order = limitOrderRouter.getOrderById(
                tokenToWethOrderBatch[i]
            );
            assert(order.orderId == bytes32(0));
        }
    }

    ///@notice Test to execute a single Token To Taxed order
    function testExecuteTokenToTaxedTokenSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        IERC20(DAI).approve(address(orderRouter), MAX_UINT);
        OrderBook.Order memory order = newMockOrder(
            DAI,
            TAXED_TOKEN,
            1,
            false,
            true,
            0,
            1,
            20000000000000000000000, //20,000
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderGroup = new OrderBook.Order[](1);
        orderGroup[0] = order;
        bytes32[] memory orderBatch = limitOrderRouter.placeOrder(orderGroup);

        //Ensure the order has been placed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );

            assert(order0.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);

        //Execute the order
        limitOrderRouter.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );
            assert(order0.orderId == bytes32(0));
        }
    }

    ///@notice Test to execute a batch of token to taxed token orders
    function testExecuteTokenToTaxedTokenBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
    }

    ///@notice Taxed Token to dai single test
    function testExecuteTaxedTokenToTokenSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(orderRouter), MAX_UINT);

        OrderBook.Order memory order = newMockOrder(
            TAXED_TOKEN,
            DAI,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderGroup = new OrderBook.Order[](1);
        orderGroup[0] = order;

        bytes32[] memory orderBatch = limitOrderRouter.placeOrder(orderGroup);

        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeOrders(orderBatch);
    }

    ///@notice Test to execute a batch of taxed token to token orders
    function testExecuteTaxedTokenToTokenBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelperUniV2), MAX_UINT);
        swapHelperUniV2.swapEthForTokenWithUniV2(10000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(orderRouter), MAX_UINT);

        bytes32[] memory orderBatch = placeNewMockTaxedToTokenBatch();

        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );
            console.log(order0.quantity);
            assert(order0.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );
            assert(order0.orderId == bytes32(0));
        }
    }

    ///@notice Test to execute a batch of taxed token to taxed token orders
    function testExecuteTaxedTokenToTaxedTokenBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelperUniV2), MAX_UINT);
        swapHelperUniV2.swapEthForTokenWithUniV2(10000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(orderRouter), MAX_UINT);

        bytes32[] memory orderBatch = placeNewMockTaxedToTaxedTokenBatch();

        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );

            assert(order0.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );
            assert(order0.orderId == bytes32(0));
        }
    }

    ///@notice Test to execute a single taxed token to taxed token order
    function testExecuteTaxedTokenToTaxedTokenSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(orderRouter), MAX_UINT);

        OrderBook.Order memory order = newMockOrder(
            TAXED_TOKEN,
            TAXED_TOKEN_1,
            1,
            false,
            true,
            3000,
            1,
            2000000000000000000000000, //2,000,000
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderGroup = new OrderBook.Order[](1);
        orderGroup[0] = order;

        bytes32[] memory orderBatch = limitOrderRouter.placeOrder(orderGroup);

        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );

            assert(order0.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        limitOrderRouter.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );
            assert(order0.orderId == bytes32(0));
        }
    }

    //----------------------------Gas Credit Tests-----------------------------------------
    ///@notice Deposit gas credits test
    function testDepositGasCredits(uint256 _amount) public {
        //deal this address max eth
        cheatCodes.deal(address(this), MAX_UINT);

        bool underflow;
        assembly {
            let bal := selfbalance()
            underflow := gt(sub(bal, _amount), bal)
        }

        if (!underflow) {
            if (address(this).balance > _amount) {
                //deposit gas credits
                (bool depositSuccess, ) = address(limitOrderRouter).call{
                    value: _amount
                }(abi.encodeWithSignature("depositGasCredits()"));

                //require that the deposit was a success
                require(
                    depositSuccess,
                    "testDepositGasCredits: deposit failed"
                );

                //get the updated gasCreditBalance for the address
                uint256 gasCreditBalance = limitOrderRouter.gasCreditBalance(
                    address(this)
                );

                //check that the creditBalance map has been updated
                require(
                    gasCreditBalance == _amount,
                    "gasCreditBalance!=_amount"
                );
            }
        }
    }

    ///@notice Fail deposit gas credits, revert InsufficientWalletBalance test
    function testFailDepositGasCredits_InsufficientWalletBalance(
        uint256 _amount
    ) public {
        //for fuzzing make sure that the input amount is < the balance of the test contract
        cheatCodes.prank(address(0x1920201785C3E370668Edac2eE36A011A4E95785));

        if (_amount > 0) {
            //deposit gas credits
            (bool depositSuccess, ) = address(limitOrderRouter).call{
                value: _amount
            }(abi.encodeWithSignature("depositGasCredits()"));

            //require that the deposit was a success
            require(
                depositSuccess,
                "testFailDepositGasCredits_InsufficientWalletBalance: deposit failed"
            );
        } else {
            require(false, "amount is 0");
        }
    }

    ///@notice Withdraw gas credit pass test
    function testWithdrawGasCredits(uint256 _amount) public {
        cheatCodes.deal(address(this), MAX_UINT);

        bool underflow;
        assembly {
            let bal := selfbalance()
            underflow := gt(sub(bal, _amount), bal)
        }

        if (!underflow) {
            //for fuzzing make sure that the input amount is < the balance of the test contract
            if (_amount > 0) {
                //deposit gas credits
                (bool depositSuccess, ) = address(limitOrderRouter).call{
                    value: _amount
                }(abi.encodeWithSignature("depositGasCredits()"));

                //require that the deposit was a success
                require(depositSuccess, "testRemoveGasCredits: deposit failed");

                //get the updated gasCreditBalance for the address
                uint256 gasCreditBalance = limitOrderRouter.gasCreditBalance(
                    address(this)
                );

                //check that the creditBalance map has been updated
                require(
                    gasCreditBalance == _amount,
                    "gasCreditBalance!=_amount"
                );

                bool withdrawSuccess = limitOrderRouter.withdrawGasCredits(
                    _amount
                );

                require(withdrawSuccess, "Unable to withdraw credits");
            }
        }
    }

    ///@notice Fail withdraw gas credits, revert InsufficientGasCreditBalance test
    function testFailWithdrawGasCredits_InsufficientGasCreditBalance(
        uint256 _amount
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);

        //ensure there is not an overflow for fuzzing
        bool overflow;
        assembly {
            overflow := lt(_amount, add(_amount, 1))
        }

        //make sure that amount+1 does not overflow
        if (!overflow) {
            if (_amount > 0) {
                //deposit gas credits
                (bool depositSuccess, ) = address(limitOrderRouter).call{
                    value: _amount
                }(abi.encodeWithSignature("depositGasCredits()"));

                //require that the deposit was a success
                require(
                    depositSuccess,
                    "testFailRemoveGasCredits_InsufficientGasCreditBalance: deposit failed"
                );

                //withdraw one more than the
                bool withdrawSuccess = limitOrderRouter.withdrawGasCredits(
                    _amount + 1
                );

                require(withdrawSuccess, "Unable to withdraw credits");
            } else {
                require(false, "input is 0");
            }
        } else {
            require(false, "overflow");
        }
    }

    ///@notice Refresh order test
    function testRefreshOrder() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(100);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        IERC20(DAI).approve(address(orderRouter), MAX_UINT);
        //Initialize a new order
        OrderBook.Order memory order = newMockOrder(
            DAI,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        bytes32 orderId = placeMockOrder(order);

        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = orderId;
        ///Ensure the order has been placed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );

            assert(order0.orderId != bytes32(0));
        }

        limitOrderRouter.refreshOrder(orderBatch);

        //Ensure the order was not cancelled and lastRefresh timestamp is updated to block.timestamp
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );
            console.log(order0.lastRefreshTimestamp);
            console.log(block.timestamp);
            assert(order0.lastRefreshTimestamp == block.timestamp);
        }
    }

    ///Test refresh order, cancel order since order has expired test
    function testRefreshOrderWithCancelOrderOrderExpired() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        IERC20(DAI).approve(address(orderRouter), MAX_UINT);

        //Initialize a new order
        OrderBook.Order memory order = newMockOrder(
            DAI,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            3000,
            0,
            0
        );

        bytes32 orderId = placeMockOrder(order);

        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = orderId;

        //Ensure order was not canceled
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );

            assert(order0.orderId != bytes32(0));
        }

        limitOrderRouter.refreshOrder(orderBatch);

        //Ensure the orders are canceled
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );
            assert(order0.orderId == bytes32(0));
        }
    }

    //block 15233771
    ///Test refresh order, Order not refreshable since last refresh timestamp isn't beyond the refresh threshold from the current block.timestamp
    function testRefreshOrderNotRefreshable() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        IERC20(DAI).approve(address(orderRouter), MAX_UINT);
        console.log(block.timestamp);
        OrderBook.Order memory order = newMockOrder(
            DAI,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            3000,
            1659049037,
            MAX_U32
        );

        bytes32 orderId = placeMockOrder(order);

        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = orderId;
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );

            assert(order0.orderId != bytes32(0));
        }

        limitOrderRouter.refreshOrder(orderBatch);

        //Ensure order was not refreshed or cancelled
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            OrderBook.Order memory order0 = limitOrderRouter.getOrderById(
                orderBatch[i]
            );
            assert(order0.orderId != bytes32(0));
            assert(order.lastRefreshTimestamp == 1659049037);
        }
    }

    receive() external payable {}

    //================================================================
    //======================= Helper functions =======================
    //================================================================

    function newMockOrder(
        address tokenIn,
        address tokenOut,
        uint128 price,
        bool buy,
        bool taxed,
        uint16 taxIn,
        uint112 amountOutMin,
        uint112 quantity,
        uint16 feeIn,
        uint16 feeOut,
        uint32 lastRefreshTimestamp,
        uint32 expirationTimestamp
    ) internal view returns (OrderBook.Order memory order) {
        //Initialize mock order
        order = OrderBook.Order({
            buy: buy,
            taxed: taxed,
            lastRefreshTimestamp: lastRefreshTimestamp,
            expirationTimestamp: expirationTimestamp,
            feeIn: feeIn,
            feeOut: feeOut,
            taxIn: taxIn,
            price: price,
            amountOutMin: amountOutMin,
            quantity: quantity,
            owner: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            orderId: bytes32(0)
        });
    }

    function placeMockOrder(OrderBook.Order memory order)
        internal
        returns (bytes32 orderId)
    {
        //create a new array of orders
        OrderBook.Order[] memory orderGroup = new OrderBook.Order[](1);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        bytes32[] memory orderIds = limitOrderRouter.placeOrder(orderGroup);

        orderId = orderIds[0];
    }

    function placeMultipleMockOrder(OrderBook.Order[] memory orderGroup)
        internal
        returns (bytes32[] memory)
    {
        //place order
        bytes32[] memory orderIds = limitOrderRouter.placeOrder(orderGroup);

        return orderIds;
    }

    function depositGasCreditsForMockOrders(uint256 _amount) public {
        (bool depositSuccess, ) = address(limitOrderRouter).call{
            value: _amount
        }(abi.encodeWithSignature("depositGasCredits()"));

        require(depositSuccess, "error when depositing gas credits");
    }

    function placeNewMockTokenToWethBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000001, //5001 DAI
            3000,
            3000,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000002, //5002 DAI
            3000,
            3000,
            0,
            MAX_U32
        );
        OrderBook.Order memory order4 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000003, //5003 DAI
            3000,
            3000,
            0,
            MAX_U32
        );
        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](4);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;
        orderBatch[3] = order4;
        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTokenToWethTaxedBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, TAXED_TOKEN);

        OrderBook.Order memory order1 = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order4 = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](4);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;
        orderBatch[3] = order4;
        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTokenToWethBatch_InvalidBatchOrdering()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000003, //5003 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_InvalidBatchOrdering()
        internal
        returns (OrderBook.Order[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000003, //5003 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockTokenToWethBatch_IncongruentTokenIn()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, UNI);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            USDC,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        bytes32[] memory mockOrderOrderIds = placeMultipleMockOrder(orderBatch);
        //place incongruent token order
        bytes32 mockOrderId = placeMockOrder(order3);

        bytes32[] memory orderIds = new bytes32[](3);
        orderIds[0] = mockOrderOrderIds[0];
        orderIds[1] = mockOrderOrderIds[1];
        orderIds[2] = mockOrderId;

        return orderIds;
    }

    function newMockTokenToWethBatch_IncongruentTokenIn()
        internal
        returns (OrderBook.Order[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, UNI);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            USDC,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockTokenToWethBatch_IncongruentTaxedTokenInBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            true,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_IncongruentTaxedTokenInBatch()
        internal
        returns (OrderBook.Order[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            true,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockTokenToWethBatch_IncongruentTokenOut()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            USDC,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_IncongruentTokenOut()
        internal
        returns (OrderBook.Order[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            USDC,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockTokenToWethBatch_IncongruentBuySellStatus()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            true,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_IncongruentBuySellStatus()
        internal
        returns (OrderBook.Order[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            true,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockWethToTokenBatch()
        internal
        returns (bytes32[] memory)
    {
        OrderBook.Order memory order1 = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockWethToTaxedBatch()
        internal
        returns (bytes32[] memory)
    {
        OrderBook.Order memory order = newMockOrder(
            WETH,
            TAXED_TOKEN,
            1,
            false,
            true,
            0,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order1 = newMockOrder(
            WETH,
            TAXED_TOKEN,
            1,
            false,
            true,
            0,
            1,
            20000000000000001, //2,000,001
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order2 = newMockOrder(
            WETH,
            TAXED_TOKEN,
            1,
            false,
            true,
            0,
            1,
            20000000000000002, //2,000,002
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order;
        orderBatch[1] = order1;
        orderBatch[2] = order2;

        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTokenToTokenBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(10000 ether, USDC);

        OrderBook.Order memory order1 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order3 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order4 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order5 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order6 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](6);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;
        orderBatch[3] = order4;
        orderBatch[4] = order5;
        orderBatch[5] = order6;

        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTaxedToTokenBatch()
        internal
        returns (bytes32[] memory)
    {
        OrderBook.Order memory order = newMockOrder(
            TAXED_TOKEN,
            DAI,
            1,
            false,
            true,
            9000,
            1,
            2000000000000000000000, //2,000,000
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order1 = newMockOrder(
            TAXED_TOKEN,
            DAI,
            1,
            false,
            true,
            9000,
            1,
            2000000000000000000000, //2,000,001
            3000,
            3000,
            0,
            MAX_U32
        );

        //    OrderBook.Order memory order2 = newMockOrder(
        //         TAXED_TOKEN_3,
        //         DAI,
        //         1,
        //         false,
        //         true,
        //         9000,
        //         1,
        //         2000000000000000000000000, //2,000,002
        //         3000,
        //         3000,
        //         0,
        //         MAX_U32
        //     );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](2);
        orderBatch[0] = order;
        orderBatch[1] = order1;
        // orderBatch[2] = order2;

        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTaxedToTaxedTokenBatch()
        internal
        returns (bytes32[] memory)
    {
        OrderBook.Order memory order = newMockOrder(
            TAXED_TOKEN,
            TAXED_TOKEN_1,
            1,
            false,
            true,
            9000,
            1,
            2000000000000000000000, //2,000,000
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](1);
        orderBatch[0] = order;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToTokenBatch()
        internal
        returns (OrderBook.Order[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }
}

contract LimitOrderRouterWrapper is LimitOrderRouter {
    constructor(
        address _gasOracle,
        address _weth,
        address _usdc,
        uint256 _executionCost,
        address _tokenToTokenExecutionAddress,
        address _taxedExecutionAddress,
        address _tokenToWethExecutionAddress,
        address _orderRouter
    )
        LimitOrderRouter(
            _gasOracle,
            _weth,
            _usdc,
            _executionCost,
            _tokenToTokenExecutionAddress,
            _taxedExecutionAddress,
            _tokenToWethExecutionAddress,
            _orderRouter
        )
    {}

    function invokeOnlyEOA() public onlyEOA {}

    function validateOrderSequencing(Order[] memory orders) public pure {
        _validateOrderSequencing(orders);
    }
}
