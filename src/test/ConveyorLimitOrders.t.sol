// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.14;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "../ConveyorLimitOrders.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "./utils/Swap.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "./utils/ScriptRunner.sol";

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

contract ConveyorLimitOrdersTest is DSTest {
    //Initialize limit-v0 contract for testing
    ConveyorLimitOrdersWrapper conveyorLimitOrders;
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
    //TODO: add taxed token
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

    uint256 alphaXDivergenceThreshold = 3402823669209385000000000000000000; //3402823669209385000000000000000000000
    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public {
        scriptRunner = new ScriptRunner();
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        swapHelper = new Swap(_sushiSwapRouterAddress, WETH);
        swapHelperUniV2 = new Swap(uniV2Addr, WETH);
        conveyorLimitOrders = new ConveyorLimitOrdersWrapper(
            0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6,
            3000000,
            _hexDems,
            _dexFactories,
            _isUniV2,
            swapRouter,
            alphaXDivergenceThreshold
        );
    }

    function testOnlyEOA() public {
        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.invokeOnlyEOA();
    }

    function testFailOnlyEOA() public {
        conveyorLimitOrders.invokeOnlyEOA();
    }

    //================================================================
    //================= Validate Order Sequence Tests ================
    //================================================================

    function testValidateOrderSequence() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);

        cheatCodes.deal(address(swapHelper), MAX_UINT);

        ConveyorLimitOrders.Order[]
            memory orderBatch = newMockTokenToTokenBatch();

        conveyorLimitOrders.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_InvalidBatchOrder() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        ConveyorLimitOrders.Order[]
            memory orderBatch = newMockTokenToWethBatch_InvalidBatchOrdering();

        conveyorLimitOrders.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentInputTokenInBatch()
        public
    {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        ConveyorLimitOrders.Order[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentTokenIn();

        conveyorLimitOrders.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentTokenOut() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        ConveyorLimitOrders.Order[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentTokenOut();
        conveyorLimitOrders.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentBuySellStatusInBatch()
        public
    {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        ConveyorLimitOrders.Order[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentBuySellStatus();
        conveyorLimitOrders.validateOrderSequencing(orderBatch);
    }

    function testFailValidateOrderSequence_IncongruentTaxedTokenInBatch()
        public
    {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        ConveyorLimitOrders.Order[]
            memory orderBatch = newMockTokenToWethBatch_IncongruentTaxedTokenInBatch();
        conveyorLimitOrders.validateOrderSequencing(orderBatch);
    }

    //================================================================
    //==================== Execution Tests ===========================
    //================================================================

    // Token to Weth Batch success
    function testExecuteTokenToWethOrderBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        IERC20(DAI).approve(address(conveyorLimitOrders), MAX_UINT);
        bytes32[] memory tokenToWethOrderBatch = placeNewMockTokenToWethBatch();

        //check that the orders have been placed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order = conveyorLimitOrders
                .getOrderById(tokenToWethOrderBatch[i]);

            assert(order.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(tokenToWethOrderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order = conveyorLimitOrders
                .getOrderById(tokenToWethOrderBatch[i]);
            assert(order.orderId == bytes32(0));
        }
    }

    function testExecuteWethToTokenSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        cheatCodes.deal(address(this), MAX_UINT);

        (bool depositSuccess, ) = address(WETH).call{value: 500000000000 ether}(
            abi.encodeWithSignature("deposit()")
        );

        require(depositSuccess, "failure when depositing ether into weth");

        IERC20(WETH).approve(address(conveyorLimitOrders), MAX_UINT);

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
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }
        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);
            assert(order0.orderId == bytes32(0));
        }
    }

    //Single order TokenToWeth success
    function testExecuteTokenToWethSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        IERC20(DAI).approve(address(conveyorLimitOrders), MAX_UINT);
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
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }
        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);
            assert(order0.orderId == bytes32(0));
        }
    }

    // Token to Weth Batch success
    function testExecuteWethToTokenOrderBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        cheatCodes.deal(address(this), MAX_UINT);
        (bool depositSuccess, ) = address(WETH).call{value: 500000000000 ether}(
            abi.encodeWithSignature("deposit()")
        );

        //require that the deposit was a success
        require(depositSuccess, "testDepositGasCredits: deposit failed");

        IERC20(WETH).approve(address(conveyorLimitOrders), MAX_UINT);

        bytes32[] memory tokenToWethOrderBatch = placeNewMockWethToTokenBatch();
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(tokenToWethOrderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }
        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(tokenToWethOrderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(tokenToWethOrderBatch[i]);
            assert(order0.orderId == bytes32(0));
        }
    }

    function testExecuteTokenToTokenSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        IERC20(DAI).approve(address(conveyorLimitOrders), MAX_UINT);
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
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);
            assert(order0.orderId == bytes32(0));
        }
    }

    // Token to Weth Batch success
    function testExecuteTokenToTokenBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        IERC20(USDC).approve(address(conveyorLimitOrders), MAX_UINT);

        bytes32[]
            memory tokenToTokenOrderBatch = placeNewMockTokenToTokenBatch();

        //check that the orders have been placed
        for (uint256 i = 0; i < tokenToTokenOrderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order = conveyorLimitOrders
                .getOrderById(tokenToTokenOrderBatch[i]);

            assert(order.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(tokenToTokenOrderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < tokenToTokenOrderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order = conveyorLimitOrders
                .getOrderById(tokenToTokenOrderBatch[i]);
            assert(order.orderId == bytes32(0));
        }
    }

    //weth to taxed token
    function testExecuteWethToTaxedTokenSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        cheatCodes.deal(address(this), MAX_UINT);

        (bool depositSuccess, ) = address(WETH).call{value: 500000000000 ether}(
            abi.encodeWithSignature("deposit()")
        );

        require(depositSuccess, "failure when depositing ether into weth");

        IERC20(WETH).approve(address(conveyorLimitOrders), MAX_UINT);
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
            ConveyorLimitOrders.Order memory order1 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);

            assert(order1.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order1 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);
            assert(order1.orderId == bytes32(0));
        }
    }

    //TODO:
    function testExecuteWethToTaxedTokenBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        cheatCodes.deal(address(this), MAX_UINT);

        (bool depositSuccess, ) = address(WETH).call{value: 500000000000 ether}(
            abi.encodeWithSignature("deposit()")
        );

        require(depositSuccess, "failure when depositing ether into weth");

        IERC20(WETH).approve(address(conveyorLimitOrders), MAX_UINT);

        bytes32[] memory wethToTaxedOrderBatch = placeNewMockWethToTaxedBatch();

        //check that the orders have been placed
        for (uint256 i = 0; i < wethToTaxedOrderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order = conveyorLimitOrders
                .getOrderById(wethToTaxedOrderBatch[i]);

            assert(order.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(wethToTaxedOrderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < wethToTaxedOrderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order = conveyorLimitOrders
                .getOrderById(wethToTaxedOrderBatch[i]);
            assert(order.orderId == bytes32(0));
        }
    }

    //weth to taxed token
    function testExecuteTaxedTokenToWethSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);

        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(conveyorLimitOrders), MAX_UINT);

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
        bytes32[] memory orderBatch = conveyorLimitOrders.placeOrder(
            orderGroup
        );
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }
        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);

        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);
            assert(order0.orderId == bytes32(0));
        }
    }

    //TODO:
    function testExecuteTaxedTokenToWethBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        IERC20(TAXED_TOKEN).approve(address(conveyorLimitOrders), MAX_UINT);

        bytes32[]
            memory tokenToWethOrderBatch = placeNewMockTokenToWethTaxedBatch();

        //check that the orders have been placed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order = conveyorLimitOrders
                .getOrderById(tokenToWethOrderBatch[i]);

            assert(order.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(tokenToWethOrderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < tokenToWethOrderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order = conveyorLimitOrders
                .getOrderById(tokenToWethOrderBatch[i]);
            assert(order.orderId == bytes32(0));
        }
    }

    //weth to taxed token
    function testExecuteTokenToTaxedTokenSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        IERC20(DAI).approve(address(conveyorLimitOrders), MAX_UINT);
        OrderBook.Order memory order = newMockOrder(
            DAI,
            TAXED_TOKEN,
            1,
            false,
            true,
            0,
            0,
            200000000000000, //20,000
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order[] memory orderGroup = new OrderBook.Order[](1);
        orderGroup[0] = order;
        bytes32[] memory orderBatch = conveyorLimitOrders.placeOrder(
            orderGroup
        );

        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);
            assert(order0.orderId == bytes32(0));
        }
    }

    //TODO: //FIXME:
    function testExecuteTokenToTaxedTokenBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
    }

    //weth to taxed token
    function testExecuteTaxedTokenToTokenSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(conveyorLimitOrders), MAX_UINT);

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
        bytes32[] memory orderBatch = conveyorLimitOrders.placeOrder(
            orderGroup
        );

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);
    }

    //TODO:
    function testExecuteTaxedTokenToTokenBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelperUniV2), MAX_UINT);
        swapHelperUniV2.swapEthForTokenWithUniV2(10000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(conveyorLimitOrders), MAX_UINT);

        bytes32[] memory orderBatch = placeNewMockTaxedToTokenBatch();

        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);
            assert(order0.orderId == bytes32(0));
        }
    }

    function testExecuteTaxedTokenToTaxedTokenBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelperUniV2), MAX_UINT);
        swapHelperUniV2.swapEthForTokenWithUniV2(10000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(conveyorLimitOrders), MAX_UINT);

        bytes32[] memory orderBatch = placeNewMockTaxedToTaxedTokenBatch();

        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);
            assert(order0.orderId == bytes32(0));
        }
    }

    //weth to taxed token
    function testExecuteTaxedTokenToTaxedTokenSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, TAXED_TOKEN);

        IERC20(TAXED_TOKEN).approve(address(conveyorLimitOrders), MAX_UINT);

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

        bytes32[] memory orderBatch = conveyorLimitOrders.placeOrder(
            orderGroup
        );

        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);

        // check that the orders have been fufilled and removed
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);
            assert(order0.orderId == bytes32(0));
        }
    }

    //----------------------------Gas Credit Tests-----------------------------------------
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
                (bool depositSuccess, ) = address(conveyorLimitOrders).call{
                    value: _amount
                }(abi.encodeWithSignature("depositGasCredits()"));

                //require that the deposit was a success
                require(
                    depositSuccess,
                    "testDepositGasCredits: deposit failed"
                );

                //get the updated gasCreditBalance for the address
                uint256 gasCreditBalance = conveyorLimitOrders.gasCreditBalance(
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

    function testFailDepositGasCredits_InsufficientWalletBalance(
        uint256 _amount
    ) public {
        //for fuzzing make sure that the input amount is < the balance of the test contract
        cheatCodes.prank(address(0x1920201785C3E370668Edac2eE36A011A4E95785));

        if (_amount > 0) {
            //deposit gas credits
            (bool depositSuccess, ) = address(conveyorLimitOrders).call{
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
                (bool depositSuccess, ) = address(conveyorLimitOrders).call{
                    value: _amount
                }(abi.encodeWithSignature("depositGasCredits()"));

                //require that the deposit was a success
                require(depositSuccess, "testRemoveGasCredits: deposit failed");

                //get the updated gasCreditBalance for the address
                uint256 gasCreditBalance = conveyorLimitOrders.gasCreditBalance(
                    address(this)
                );

                //check that the creditBalance map has been updated
                require(
                    gasCreditBalance == _amount,
                    "gasCreditBalance!=_amount"
                );

                bool withdrawSuccess = conveyorLimitOrders.withdrawGasCredits(
                    _amount
                );

                require(withdrawSuccess, "Unable to withdraw credits");
            }
        }
    }

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
                (bool depositSuccess, ) = address(conveyorLimitOrders).call{
                    value: _amount
                }(abi.encodeWithSignature("depositGasCredits()"));

                //require that the deposit was a success
                require(
                    depositSuccess,
                    "testFailRemoveGasCredits_InsufficientGasCreditBalance: deposit failed"
                );

                //withdraw one more than the
                bool withdrawSuccess = conveyorLimitOrders.withdrawGasCredits(
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

    function testRefreshOrder() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        IERC20(DAI).approve(address(conveyorLimitOrders), MAX_UINT);
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
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }

        conveyorLimitOrders.refreshOrder(orderBatch);

        //Ensure the order was not cancelled and lastRefresh timestamp is updated to block.timestamp
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);
            console.log(order0.lastRefreshTimestamp);
            console.log(block.timestamp);
            assert(order0.lastRefreshTimestamp == block.timestamp);
        }
    }

    function testRefreshOrderWithCancelOrderOrderExpired() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        IERC20(DAI).approve(address(conveyorLimitOrders), MAX_UINT);

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
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }

        conveyorLimitOrders.refreshOrder(orderBatch);

        //Ensure the orders are canceled
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);
            assert(order0.orderId == bytes32(0));
        }
    }

    //block 15233771
    function testRefreshOrderNotRefreshable() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        IERC20(DAI).approve(address(conveyorLimitOrders), MAX_UINT);
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
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);

            assert(order0.orderId != bytes32(0));
        }

        conveyorLimitOrders.refreshOrder(orderBatch);

        //Ensure order was not refreshed or cancelled
        for (uint256 i = 0; i < orderBatch.length; ++i) {
            ConveyorLimitOrders.Order memory order0 = conveyorLimitOrders
                .getOrderById(orderBatch[i]);
            assert(order0.orderId != bytes32(0));
            assert(order.lastRefreshTimestamp == 1659049037);
        }
    }

    receive() external payable {
        // console.log("receive invoked");
    }

    //================================================================
    //======================= Order Simulation Unit Tests ============
    //================================================================
    function testFindBestTokenToTokenExecutionPrice() public {
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 18;
        decimals[1] = 18;

        ConveyorLimitOrders.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice = OrderRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 8014835235973799779324680,
                    aToWethReserve1: 4595913824638810919416,
                    wethToBReserve0: 1414776373420924126438282,
                    wethToBReserve1: 7545889283955278550784,
                    price: 36584244663945024000000000000000000000,
                    lpAddressAToWeth: 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11,
                    lpAddressWethToB: 0xd3d2E2692501A5c9Ca623199D38826e513033a17
                });

        ConveyorLimitOrders.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice1 = OrderRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 8014835235973799779324680,
                    aToWethReserve1: 4595913824638810919416,
                    wethToBReserve0: 1414776373420924126438282,
                    wethToBReserve1: 7545889283955278550784,
                    price: 36584244663945024000000000000000000001,
                    lpAddressAToWeth: 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11,
                    lpAddressWethToB: 0xd3d2E2692501A5c9Ca623199D38826e513033a17
                });

        ConveyorLimitOrders.TokenToTokenExecutionPrice[]
            memory executionPrices = new OrderRouter.TokenToTokenExecutionPrice[](
                2
            );
        executionPrices[0] = tokenToTokenExecutionPrice;
        executionPrices[1] = tokenToTokenExecutionPrice1;

        uint256 bestPriceIndexBuy = conveyorLimitOrders
            .findBestTokenToTokenExecutionPrice(executionPrices, true);
        uint256 bestPriceIndexSell = conveyorLimitOrders
            .findBestTokenToTokenExecutionPrice(executionPrices, false);

        assertEq(bestPriceIndexBuy, 0);
        assertEq(bestPriceIndexSell, 1);
    }

    function testSimulateAToBPriceChangeV2ReserveOutputs(uint112 _amountIn)
        public
    {
        uint112 reserveAIn = 7957765096999155822679329;
        uint112 reserveBIn = 4628057647836077568601;

        address pool = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
        bool underflow;
        assembly {
            underflow := lt(reserveAIn, _amountIn)
        }

        if (!underflow) {
            if (_amountIn != 0) {
                (, uint128 reserveA, uint128 reserveB, ) = conveyorLimitOrders
                    .simulateAToBPriceChange(
                        _amountIn,
                        reserveAIn,
                        reserveBIn,
                        pool,
                        true
                    );
                string memory path = "scripts/simulateNewReserves.py";
                string[] memory args = new string[](3);
                args[0] = uint2str(_amountIn);
                args[1] = uint2str(reserveAIn);
                args[2] = uint2str(reserveBIn);
                bytes memory outputReserveB = scriptRunner.runPythonScript(
                    path,
                    args
                );
                uint256 expectedReserveB = bytesToUint(outputReserveB);

                uint256 expectedReserveA = reserveAIn + _amountIn;

                assertEq(reserveA, expectedReserveA);

                assertEq(reserveB / 10**9, expectedReserveB / 10**9);
            }
        }
    }

    function testSimulateAToBPriceChangeV2SpotPrice(uint112 _amountIn) public {
        uint112 reserveAIn = 7957765096999155822679329;
        uint112 reserveBIn = 4628057647836077568601;

        address pool = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
        bool underflow;
        assembly {
            underflow := lt(reserveAIn, _amountIn)
        }

        if (!underflow) {
            if (_amountIn != 0) {
                (uint256 spotPrice, , , ) = conveyorLimitOrders
                    .simulateAToBPriceChange(
                        _amountIn,
                        reserveAIn,
                        reserveBIn,
                        pool,
                        true
                    );
                string memory path = "scripts/simulateSpotPriceChange.py";
                string[] memory args = new string[](3);
                args[0] = uint2str(_amountIn);
                args[1] = uint2str(reserveAIn);
                args[2] = uint2str(reserveBIn);
                bytes memory spotOut = scriptRunner.runPythonScript(path, args);
                uint256 spotPriceExpected = bytesToUint(spotOut);

                assertEq(spotPrice >> 75, spotPriceExpected >> 75);
            }
        }
    }

    //Block # 15233771
    function testSimulateAToBPriceChangeV3() public {
        address poolAddress = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
        uint128 alphaX = 5000000000000000000000;

        (uint256 spotPrice, , , uint128 amountOut) = conveyorLimitOrders
            .simulateAToBPriceChange(alphaX, 0, 0, poolAddress, true);
        assertEq(spotPrice, 195185994537407119486875905535508480);
        assertEq(amountOut, 2859640483990650224);
    }

    //Block # 15233771
    function testSimulateWethToBPriceChangeV3() public {
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 18;
        decimals[1] = 18;
        //Weth/Uni
        ConveyorLimitOrders.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice = OrderRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 0,
                    aToWethReserve1: 0,
                    wethToBReserve0: 0,
                    wethToBReserve1: 0,
                    price: 0,
                    lpAddressAToWeth: address(0),
                    lpAddressWethToB: 0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801
                });

        (uint256 newSpotPriceB, , ) = conveyorLimitOrders
            .simulateWethToBPriceChange(
                5000000000000000000000,
                tokenToTokenExecutionPrice
            );
        assertEq(38416481291436668068511433527512398823424, newSpotPriceB);
    }

    //Block # 15233771
    function testSimulateAToWethPriceChangeV3() public {
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 18;
        decimals[1] = 18;
        //Weth/Uni
        ConveyorLimitOrders.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice = OrderRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 0,
                    aToWethReserve1: 0,
                    wethToBReserve0: 0,
                    wethToBReserve1: 0,
                    price: 0,
                    lpAddressAToWeth: 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8,
                    lpAddressWethToB: address(0)
                });

        (uint256 newSpotPriceA, , , uint128 amountOut) = conveyorLimitOrders
            .simulateAToWethPriceChange(
                5000000000000000000000,
                tokenToTokenExecutionPrice
            );
        assertEq(newSpotPriceA, 195185994537407119486875905535508480);
        assertEq(amountOut, 2859640483990650224);
    }

    //Block # 15233771
    function testSimulateWethToBPriceChangeV2() public {
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 18;
        decimals[1] = 18;
        //Weth/Uni
        ConveyorLimitOrders.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice = OrderRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 8014835235973799779324680,
                    aToWethReserve1: 4595913824638810919416,
                    wethToBReserve0: 1414776373420924126438282,
                    wethToBReserve1: 7545889283955278550784,
                    price: 0,
                    lpAddressAToWeth: 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11,
                    lpAddressWethToB: 0xd3d2E2692501A5c9Ca623199D38826e513033a17
                });

        (uint256 newSpotPriceB, , ) = conveyorLimitOrders
            .simulateWethToBPriceChange(
                5000000000000000000,
                tokenToTokenExecutionPrice
            );
        assertEq(newSpotPriceB, 63714967732803596813954797656252367241216);
    }

    //Block # 15233771
    function testSimulateAToWethPriceChangeV2() public {
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 18;
        decimals[1] = 18;
        //Weth/Uni
        ConveyorLimitOrders.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice = OrderRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 8014835235973799779324680,
                    aToWethReserve1: 4595913824638810919416,
                    wethToBReserve0: 1414776373420924126438282,
                    wethToBReserve1: 7545889283955278550784,
                    price: 0,
                    lpAddressAToWeth: 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11,
                    lpAddressWethToB: 0xd3d2E2692501A5c9Ca623199D38826e513033a17
                });

        (uint256 newSpotPriceA, , , uint128 amountOut) = conveyorLimitOrders
            .simulateAToWethPriceChange(
                50000000000000000000000,
                tokenToTokenExecutionPrice
            );
        assertEq(newSpotPriceA, 192714735056741134836410079523110912);
        assertEq(amountOut, 28408586008574759898);
    }

    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + (j % 10)));
            j /= 10;
        }
        str = string(bstr);
    }

    function bytesToUint(bytes memory b) internal pure returns (uint256) {
        uint256 number;
        for (uint256 i = 0; i < b.length; i++) {
            number =
                number +
                uint256(uint8(b[i])) *
                (2**(8 * (b.length - (i + 1))));
        }
        return number;
    }

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
    ) internal view returns (ConveyorLimitOrders.Order memory order) {
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

    function placeMockOrder(ConveyorLimitOrders.Order memory order)
        internal
        returns (bytes32 orderId)
    {
        //create a new array of orders
        ConveyorLimitOrders.Order[]
            memory orderGroup = new ConveyorLimitOrders.Order[](1);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        bytes32[] memory orderIds = conveyorLimitOrders.placeOrder(orderGroup);

        orderId = orderIds[0];
    }

    function placeMultipleMockOrder(
        ConveyorLimitOrders.Order[] memory orderGroup
    ) internal returns (bytes32[] memory) {
        //place order
        bytes32[] memory orderIds = conveyorLimitOrders.placeOrder(orderGroup);

        return orderIds;
    }

    function depositGasCreditsForMockOrders(uint256 _amount) public {
        (bool depositSuccess, ) = address(conveyorLimitOrders).call{
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
        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](4);
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](4);
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_InvalidBatchOrdering()
        internal
        returns (ConveyorLimitOrders.Order[] memory)
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](3);
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
        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](3);
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
        returns (ConveyorLimitOrders.Order[] memory)
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](3);
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_IncongruentTaxedTokenInBatch()
        internal
        returns (ConveyorLimitOrders.Order[] memory)
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](3);
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_IncongruentTokenOut()
        internal
        returns (ConveyorLimitOrders.Order[] memory)
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](3);
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_IncongruentBuySellStatus()
        internal
        returns (ConveyorLimitOrders.Order[] memory)
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](3);
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](3);
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](3);
        orderBatch[0] = order;
        orderBatch[1] = order1;
        orderBatch[2] = order2;

        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTokenToTokenBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);

        OrderBook.Order memory order1 = newMockOrder(
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

        OrderBook.Order memory order2 = newMockOrder(
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

        OrderBook.Order memory order3 = newMockOrder(
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

        OrderBook.Order memory order4 = newMockOrder(
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](6);
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](2);
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](1);
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

        ConveyorLimitOrders.Order[]
            memory orderBatch = new ConveyorLimitOrders.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }
}

contract ConveyorLimitOrdersWrapper is ConveyorLimitOrders {
    constructor(
        address _gasOracle,
        address _weth,
        address _usdc,
        address _quoterAddress,
        uint256 _executionCost,
        bytes32[] memory _initBytecodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2,
        address _swapRouter,
        uint256 _alphaXDivergenceThreshold
    )
        ConveyorLimitOrders(
            _gasOracle,
            _weth,
            _usdc,
            _quoterAddress,
            _executionCost,
            _initBytecodes,
            _dexFactories,
            _isUniV2,
            _swapRouter,
            _alphaXDivergenceThreshold
        )
    {}

    function invokeOnlyEOA() public onlyEOA {}

    function executeTokenToWethOrders(Order[] calldata orders) external {
        _executeTokenToWethOrders(orders);
    }

    function validateOrderSequencing(Order[] memory orders) public pure {
        _validateOrderSequencing(orders);
    }

    function simulateAToBPriceChange(
        uint128 alphaX,
        uint128 reserveA,
        uint128 reserveB,
        address pool,
        bool isTokenToWeth
    )
        public
        returns (
            uint256,
            uint128,
            uint128,
            uint128
        )
    {
        return
            _simulateAToBPriceChange(
                alphaX,
                reserveA,
                reserveB,
                pool,
                isTokenToWeth
            );
    }

    function simulateAToWethPriceChange(
        uint128 alphaX,
        TokenToTokenExecutionPrice memory executionPrice
    )
        public
        returns (
            uint256 newSpotPriceA,
            uint128 newReserveAToken,
            uint128 newReserveAWeth,
            uint128 amountOut
        )
    {
        return _simulateAToWethPriceChange(alphaX, executionPrice);
    }

    function findBestTokenToTokenExecutionPrice(
        TokenToTokenExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) public returns (uint256 bestPriceIndex) {
        return _findBestTokenToTokenExecutionPrice(executionPrices, buyOrder);
    }

    function simulateWethToBPriceChange(
        uint128 alphaX,
        TokenToTokenExecutionPrice memory executionPrice
    )
        public
        returns (
            uint256 newSpotPriceB,
            uint128 newReserveBWeth,
            uint128 newReserveBToken
        )
    {
        return _simulateWethToBPriceChange(alphaX, executionPrice);
    }
}
