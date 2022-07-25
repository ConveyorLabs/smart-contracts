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

    Swap swapHelper;

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
    address TAXED_TOKEN = 0x8B3192f5eEBD8579568A2Ed41E6FEB402f93f73F;
    address TAXED_TOKEN_1 = address(0);

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

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        swapHelper = new Swap(_sushiSwapRouterAddress, WETH);

        conveyorLimitOrders = new ConveyorLimitOrdersWrapper(
            0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            5,
            2592000,
            3000000,
            _hexDems,
            _dexFactories,
            _isUniV2
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
    //================= Batch Orders Tests ===========================
    //================================================================

    function testBatchTokenToWethOrders() public {}

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

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);
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

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);
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

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(tokenToWethOrderBatch);
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

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);
    }

    // Token to Weth Batch success
    function testExecuteTokenToTokenBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        swapHelper.swapEthForTokenWithUniV2(100000 ether, UNI);

        IERC20(DAI).approve(address(conveyorLimitOrders), MAX_UINT);

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

        OrderBook.Order memory order = newMockOrder(
            WETH,
            TAXED_TOKEN,
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

        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = order.orderId;

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);
    }

    //TODO:
    function testExecuteWethToTaxedTokenBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);

        // bytes32[] memory tokenToWethOrderBatch = newMockTokenToTokenBatch();
        // conveyorLimitOrders.executeOrders(tokenToWethOrderBatch);
    }

    //weth to taxed token
    function testExecuteTaxedTokenToWethSingle() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);

        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

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

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);
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

        OrderBook.Order memory order = newMockOrder(
            DAI,
            TAXED_TOKEN,
            1,
            false,
            true,
            4000,
            0,
            20000000000000000, //2,000,000
            3000,
            3000,
            0,
            MAX_U32
        );

        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = order.orderId;

        cheatCodes.prank(tx.origin);
        conveyorLimitOrders.executeOrders(orderBatch);
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
    }

    //TODO: FIXME:
    //weth to taxed token
    function testExecuteTaxedTokenToTaxedTokenSingle() public {}

    //TODO:
    function testExecuteTaxedTokenToTaxedTokenBatch() public {
        cheatCodes.deal(address(this), MAX_UINT);
        depositGasCreditsForMockOrders(MAX_UINT);
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

    function testFailDepositGasCredits_InsufficientGasCreditBalanceForOrderExecution(
        uint256 _amount
    ) public {
        //deal this address max eth
        cheatCodes.deal(address(this), MAX_UINT);

        //for fuzzing make sure that the input amount is < the balance of the test contract
        if (address(this).balance - _amount > _amount) {
            //deposit gas credits
            (bool depositSuccess, ) = address(conveyorLimitOrders).call{
                value: _amount
            }(abi.encodeWithSignature("depositGasCredits()"));

            //require that the deposit was a success
            require(depositSuccess, "testDepositGasCredits: deposit failed");

            //get the updated gasCreditBalance for the address
            uint256 gasCreditBalance = conveyorLimitOrders.gasCreditBalance(
                address(this)
            );

            //check that the creditBalance map has been updated
            require(gasCreditBalance == _amount);
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

    function testFailRemoveGasCredits_InsufficientGasCreditBalance(
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
        //deal this address max eth
        cheatCodes.deal(address(this), MAX_UINT);

        // cheatCodes.deal(address(swapHelper), MAX_UINT);

        cheatCodes.prank(address(this));
        (bool depositSuccess, ) = address(conveyorLimitOrders).call{
            value: 90000000000000000000000000090000000
        }(abi.encodeWithSignature("depositGasCredits()"));

        uint256 gasCreditBalance = conveyorLimitOrders.gasCreditBalance(
            address(this)
        );

        //require that the deposit was a success
        require(depositSuccess, "testRefreshOrder: deposit failed");

        swapHelper.swapEthForTokenWithUniV2(5 ether, swapToken);

        ConveyorLimitOrders.Order memory order = OrderBook.Order({
            buy: true,
            taxed: false,
            lastRefreshTimestamp: 0,
            expirationTimestamp: 2419200,
            feeIn: 0,
            feeOut: 0,
            taxIn: 0,
            price: 16602069666338596454400,
            amountOutMin: 6900000000000000000,
            quantity: 0,
            owner: address(this),
            tokenIn: swapToken,
            tokenOut: WETH,
            orderId: bytes32(0)
        });

        bytes32 orderId = placeMockOrder(order);

        bool refreshSuccess = conveyorLimitOrders.refreshOrder(orderId);

        require(refreshSuccess, "Order Refresh failed");
    }

    function testFailRefreshOrder_CancelOrder_InsufficientGasCreditBalance()
        public
    {
        //deal this address max eth
        cheatCodes.deal(address(this), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(5 ether, swapToken);
        ConveyorLimitOrders.Order memory order = OrderBook.Order({
            buy: true,
            taxed: false,
            lastRefreshTimestamp: 0,
            expirationTimestamp: 2419200,
            feeIn: 0,
            feeOut: 0,
            taxIn: 0,
            price: 16602069666338596454400,
            amountOutMin: 6900000000000000000,
            quantity: 0,
            owner: address(this),
            tokenIn: swapToken,
            tokenOut: WETH,
            orderId: bytes32(0)
        });
        bytes32 orderId = placeMockOrder(order);
        bool refreshSuccess = conveyorLimitOrders.refreshOrder(orderId);
        require(refreshSuccess == true, "Order Refresh failed");
    }

    function testFailRefreshOrder_OrderNotRefreshable() public {
        //deal this address max eth
        cheatCodes.deal(address(this), MAX_UINT);

        cheatCodes.prank(address(this));

        (bool depositSuccess, ) = address(conveyorLimitOrders).call{
            value: 90000000000000000000000000090000000
        }(abi.encodeWithSignature("depositCredits()"));

        //require that the deposit was a success
        require(depositSuccess, "testDepositGasCredits: deposit failed");

        swapHelper.swapEthForTokenWithUniV2(5 ether, swapToken);
        ConveyorLimitOrders.Order memory order = OrderBook.Order({
            buy: true,
            taxed: false,
            lastRefreshTimestamp: 0,
            expirationTimestamp: 0x0000000000000000000000000000000000000000000000000000000000c30102,
            feeIn: 0,
            feeOut: 0,
            taxIn: 0,
            price: 16602069666338596454400,
            amountOutMin: 6900000000000000000,
            quantity: 0,
            owner: address(this),
            tokenIn: swapToken,
            tokenOut: WETH,
            orderId: bytes32(0)
        });

        bytes32 orderId = placeMockOrder(order);

        bool refreshSuccess = conveyorLimitOrders.refreshOrder(orderId);

        require(refreshSuccess == true, "Order Refresh failed");
    }

    function testFailRefreshOrder_InsufficientGasCreditBalance() public {
        //deal this address max eth
        cheatCodes.deal(address(this), MAX_UINT);

        swapHelper.swapEthForTokenWithUniV2(5 ether, swapToken);

        ConveyorLimitOrders.Order memory order = OrderBook.Order({
            buy: true,
            taxed: false,
            lastRefreshTimestamp: 0,
            expirationTimestamp: 0x0000000000000000000000000000000000000000000000000000000000c30102,
            feeIn: 0,
            feeOut: 0,
            taxIn: 0,
            price: 16602069666338596454400,
            amountOutMin: 6900000000000000000,
            quantity: 0,
            owner: address(this),
            tokenIn: swapToken,
            tokenOut: WETH,
            orderId: bytes32(0)
        });

        bytes32 orderId = placeMockOrder(order);

        bool refreshSuccess = conveyorLimitOrders.refreshOrder(orderId);

        require(refreshSuccess == true, "Order Refresh failed");
    }

    function testFail_InsufficientGasCreditBalanceForOrderExecution() public {
        //deal this address max eth
        cheatCodes.deal(address(this), MAX_UINT);

        // cheatCodes.deal(address(swapHelper), MAX_UINT);

        cheatCodes.prank(address(this));
        (bool depositSuccess, ) = address(conveyorLimitOrders).call{value: 100}(
            abi.encodeWithSignature("depositCredits()")
        );

        //require that the deposit was a success
        require(depositSuccess, "testDepositGasCredits: deposit failed");

        swapHelper.swapEthForTokenWithUniV2(5 ether, swapToken);

        ConveyorLimitOrders.Order memory order = OrderBook.Order({
            buy: true,
            taxed: false,
            lastRefreshTimestamp: 0x0000000000000000000000000000000000000000000000000000000062c30102,
            expirationTimestamp: 2419200,
            feeIn: 3000,
            feeOut: 0,
            taxIn: 0,
            price: 16602069666338596454400,
            amountOutMin: 6900000000000000000,
            quantity: 0,
            owner: address(this),
            tokenIn: swapToken,
            tokenOut: WETH,
            orderId: bytes32(0)
        });

        bytes32 orderId = placeMockOrder(order);

        bool refreshSuccess = conveyorLimitOrders.refreshOrder(orderId);

        require(refreshSuccess == true, "Order Refresh failed");
    }

    receive() external payable {
        // console.log("receive invoked");
    }

    // function testRefreshOrderFailOrderNotRefreshable(){
    //     OrderBook.Order memory order = OrderBook.Order({
    //         tokenIn: tokenIn,
    //         tokenOut: tokenOut,
    //         orderId: bytes32(0),
    //         buy: buy,
    //         taxed: taxed,
    //         lastRefreshTimestamp: 0,
    //         expirationTimestamp: 2419200,
    //         price: price,
    //         amountOutMin: amountOutMin,
    //         quantity: quantity,
    //         owner: msg.sender
    //     });
    // }

    // function testFailRemoveGasCredits_InsufficientGasCreditBalanceForOrderExecution(
    //     uint256 _amount
    // ) public {}

    // function testSimulatePriceChange() public {}

    // function testSimulatePriceChange() public {
    //     uint128[] memory reserves = new uint128[](2);
    //     reserves[0]= 82965859*2**18;
    //     reserves[1]=42918*2**18;
    //     uint128 alphaX = 1000000*2**18;
    //     console.logString("TEST SIMULATE PRICE CHANGE");
    //     uint256 spot = conveyorLimitOrders.simulatePriceChange(alphaX, reserves);
    //     assertEq(0x000000000000000000000000000007bc019f93509a129114c8df914ab5340000, spot);

    // }

    //----------------------------Single Swap Tests -----------------------------------------

    // function testSwapTokenToTokenOnBestDex() public {
    //     cheatCodes.deal(address(swapHelper), MAX_UINT);

    //     address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    //     //get the token in
    //     uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
    //         10000000000000000,
    //         tokenIn
    //     );

    //     address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     address lp = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    //     uint256 amountOutMin = 10000000000;

    //     IERC20(tokenIn).approve(address(conveyorLimitOrders), amountReceived);

    //     conveyorLimitOrders.swapTokenToTokenOnBestDex(
    //         tokenIn,
    //         tokenOut,
    //         amountReceived,
    //         amountOutMin,
    //         100,
    //         address(this)
    //     );
    // }

    // function testSwapETHToTokenOnBestDex() public {
    //     cheatCodes.deal(address(swapHelper), MAX_UINT);

    //     address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     address lp = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    //     uint256 amountOutMin = 10000000000;

    //     IERC20(tokenIn).approve(address(conveyorLimitOrders), 10000);

    //Swap Token to Token on best Dex tests
    function testSwapTokenToTokenOnBestDex() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            10000000000000000,
            tokenIn
        );

        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        uint256 amountOutMin = amountReceived - 1;

        IERC20(tokenIn).approve(address(conveyorLimitOrders), amountReceived);
        address reciever = address(this);
        conveyorLimitOrders.swapTokenToTokenOnBestDex(
            tokenIn,
            tokenOut,
            amountReceived,
            amountOutMin,
            500,
            reciever,
            address(this)
        );
    }

    function testSwapTokenToEthOnBestDex() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            10000000000000000,
            tokenIn
        );

        uint256 amountOutMin = amountReceived - 1;

        IERC20(tokenIn).approve(address(conveyorLimitOrders), amountReceived);
        console.logUint(address(this).balance);
        conveyorLimitOrders.swapTokenToETHOnBestDex(
            tokenIn,
            amountReceived,
            amountOutMin,
            500
        );
        console.logUint(address(this).balance);
    }

    function testSwapEthToTokenOnBestDex() public {
        cheatCodes.deal(address(this), MAX_UINT);

        address tokenOut = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        (bool depositSuccess, ) = address(conveyorLimitOrders).call{
            value: 1000000000000000000
        }(
            abi.encodeWithSignature(
                "swapETHToTokenOnBestDex(address,uint256,uint256,uint24)",
                tokenOut,
                1000000000000000000,
                10000,
                500
            )
        );
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
        OrderBook.Order memory order4 = newMockOrder(
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

    function placeNewMockTokenToTokenBatch()
        internal
        returns (bytes32[] memory)
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
        uint256 _refreshFee,
        uint256 _refreshInterval,
        uint256 _executionCost,
        bytes32[] memory _initBytecodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2
    )
        ConveyorLimitOrders(
            _gasOracle,
            _weth,
            _usdc,
            _refreshFee,
            _refreshInterval,
            _executionCost,
            _initBytecodes,
            _dexFactories,
            _isUniV2
        )
    {}

    function invokeOnlyEOA() public onlyEOA {}

    function executeTokenToWethOrders(Order[] calldata orders) external {
        _executeTokenToWethOrders(orders);
    }

    function validateOrderSequencing(Order[] memory orders) public pure {
        _validateOrderSequencing(orders);
    }
}
