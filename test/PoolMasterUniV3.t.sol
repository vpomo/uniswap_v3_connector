// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {Test, console2} from "forge-std/Test.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {PoolMasterUniV3} from "../src/PoolMasterUniV3.sol";
import {IPoolMaster} from "../src/interfaces/IPoolMaster.sol";
import {MockErc20Token} from "../src/mock/MockErc20Token.sol";

import "../src/interfaces/INonfungiblePositionManager.sol";
import {TickMath} from "../src/libraries/TickMath.sol";


contract PoolMasterTest is Test {
    // Источник: https://docs.uniswap.org/contracts/v3/reference/deployments
    address internal constant ARBITRUM_NPM = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address internal constant ARBITRUM_UNIVERSAL_ROUTER = 0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3;
    address internal constant ARBITRUM_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    string internal ARBITRUM_MAINNET_RPC_URL = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    PoolMasterUniV3 internal poolMaster;
    MockErc20Token internal token0;
    MockErc20Token internal token1;
    INonfungiblePositionManager internal npm = INonfungiblePositionManager(ARBITRUM_NPM);

    address internal owner = makeAddr("owner");
    address internal user = makeAddr("user");

    uint24 internal constant POOL_FEE = 3000; // 0.3%
    int24 internal constant TICK_SPACING = 60; // Для 0.3% пула
    uint256 internal constant INITIAL_LIQUIDITY_AMOUNT = 100 ether;
    uint256 internal constant SWAP_AMOUNT = 1 ether;

    function setUp() public {
        vm.createSelectFork(ARBITRUM_MAINNET_RPC_URL);

        poolMaster = new PoolMasterUniV3();
        poolMaster.initialize(owner, ARBITRUM_NPM, ARBITRUM_UNIVERSAL_ROUTER, ARBITRUM_PERMIT2);

        MockErc20Token tokenA = new MockErc20Token();
        MockErc20Token tokenB = new MockErc20Token();

        if (address(tokenA) < address(tokenB)) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }

        token0.mint(owner, 1_000_000 ether);
        token1.mint(owner, 1_000_000 ether);
        token0.mint(user, 1_000_000 ether);
        token1.mint(user, 1_000_000 ether);
    }

    // ===============================================================
    // Тесты инициализации и контроля доступа
    // ===============================================================

    function test_Initialize() public view {
        assertEq(address(poolMaster.nonfungiblePositionManager()), ARBITRUM_NPM, "NPM address is incorrect");
        assertEq(address(poolMaster.universalRouter()), ARBITRUM_UNIVERSAL_ROUTER, "Universal Router address is incorrect");
        assertEq(poolMaster.permit2(), ARBITRUM_PERMIT2, "Permit2 address is incorrect");
    }

    function test_Revert_InitializeWithZeroAddress() public {
        PoolMasterUniV3 newPoolMaster = new PoolMasterUniV3();
        vm.expectRevert("PoolMaster: can not be zero address");
        newPoolMaster.initialize(address(0), ARBITRUM_NPM, ARBITRUM_UNIVERSAL_ROUTER, ARBITRUM_PERMIT2);
    }

    function test_Revert_OwnerFunctions_WhenCalledByNonOwner() public {
        vm.startPrank(user);

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                user, poolMaster.ADMIN_ROLE()
            )
        );
        poolMaster.createPool(address(token0), address(token1), POOL_FEE, TICK_SPACING, sqrtPriceX96);

        vm.expectRevert(
            abi.encodeWithSelector(
        bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                user, poolMaster.ADMIN_ROLE()
            )
        );
        poolMaster.mintPosition(0, 1, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                user, poolMaster.ADMIN_ROLE()
            )
        );
        poolMaster.rescue(payable(user), 1 ether);

        vm.stopPrank();
    }

    function test_FullWorkflow_Create_Mint_Increase_Decrease_Burn() public {
        // --- 1. Создание пула ---
        vm.prank(owner);
        uint160 initialSqrtPriceX96 = TickMath.getSqrtRatioAtTick(0); // 1:1 price
        poolMaster.createPool(address(token0), address(token1), POOL_FEE, TICK_SPACING, initialSqrtPriceX96);

        assertNotEq(address(poolMaster.pool()), address(0), "Pool should be created");
        assertEq(poolMaster.token0(), address(token0), "token0 address is incorrect");
        assertEq(poolMaster.token1(), address(token1), "token1 address is incorrect");

        vm.startPrank(owner);
        // Переводим токены на контракт для создания ликвидности
        token0.transfer(address(poolMaster), INITIAL_LIQUIDITY_AMOUNT);
        token1.transfer(address(poolMaster), INITIAL_LIQUIDITY_AMOUNT);

        // Задаем широкий диапазон тиков
        int24 lowerTick = -TICK_SPACING * 100;
        int24 upperTick = TICK_SPACING * 100;

        (uint256 tokenId, uint128 liquidity, , ) = poolMaster.mintPosition(
            lowerTick,
            upperTick,
            INITIAL_LIQUIDITY_AMOUNT,
            INITIAL_LIQUIDITY_AMOUNT
        );

        assertTrue(tokenId > 0, "TokenId should be greater than 0");
        assertTrue(liquidity > 0, "Liquidity should be greater than 0");
        IPoolMaster.PositionInfo memory info = poolMaster.getPosition(0);
        assertTrue(info.tokenId > 0, "Position should be added to the array");
        assertEq(npm.ownerOf(tokenId), address(poolMaster), "PoolMaster should own the NFT");
        vm.stopPrank();

        // --- 3. Увеличение ликвидности ---
        vm.startPrank(owner);
        uint256 increaseAmount = 50 ether;
        token0.transfer(address(poolMaster), increaseAmount);
        token1.transfer(address(poolMaster), increaseAmount);

        (,,,,,,,uint128 liquidityBefore,,,,) = npm.positions(tokenId);
        poolMaster.increaseLiquidity(tokenId, uint128(increaseAmount), uint128(increaseAmount));
        (,,,,,,,uint128 liquidityAfter,,,,) = npm.positions(tokenId);

        assertGt(liquidityAfter, liquidityBefore, "Liquidity should increase");
        vm.stopPrank();

        // --- 4. Уменьшение ликвидности ---
        vm.startPrank(owner);
        uint128 decreaseLiquidityAmount = liquidity / 2;
        uint256 balance0Before = token0.balanceOf(address(poolMaster));
        uint256 balance1Before = token1.balanceOf(address(poolMaster));

        poolMaster.decreaseLiquidity(tokenId, decreaseLiquidityAmount, 0, 0);

        (,,,,,,,uint128 liquidityAfterDecrease,,,,) = npm.positions(tokenId);
        uint256 balance0After = token0.balanceOf(address(poolMaster));
        uint256 balance1After = token1.balanceOf(address(poolMaster));

        assertLt(liquidityAfterDecrease, liquidityAfter, "Liquidity should decrease");
        assertGt(balance0After, balance0Before, "Token0 balance should increase after decrease");
        assertGt(balance1After, balance1Before, "Token1 balance should increase after decrease");
        vm.stopPrank();

        // --- 5. Сжигание позиции ---
        vm.startPrank(owner);
        balance0Before = token0.balanceOf(address(poolMaster));
        balance1Before = token1.balanceOf(address(poolMaster));

        poolMaster.burnPosition(tokenId, 0, 0);

        balance0After = token0.balanceOf(address(poolMaster));
        balance1After = token1.balanceOf(address(poolMaster));

        assertGt(balance0After, balance0Before, "Token0 balance should increase after burn");
        assertGt(balance1After, balance1Before, "Token1 balance should increase after burn");

        // Проверяем, что NFT сожжен
        vm.expectRevert("ERC721: owner query for nonexistent token");
        npm.ownerOf(tokenId);
        vm.stopPrank();
    }

    // ===============================================================
    // Тесты для публичных функций
    // ===============================================================

    function test_SwapExactInputSingle() public {
        // --- Подготовка: создаем пул и добавляем ликвидность ---
        _createPoolAndMintPosition();

        vm.startPrank(user);
        token0.approve(address(poolMaster), SWAP_AMOUNT);

        uint256 userBalance0Before = token0.balanceOf(user);
        uint256 userBalance1Before = token1.balanceOf(user);

        uint256 amountOut = poolMaster.swapExactInputSingle(SWAP_AMOUNT, 0, true);

        uint256 userBalance0After = token0.balanceOf(user);
        uint256 userBalance1After = token1.balanceOf(user);

        assertTrue(amountOut > 0, "Amount out should be greater than 0");
        assertEq(userBalance0After, userBalance0Before - SWAP_AMOUNT, "User token0 balance should decrease by swap amount");
        assertTrue(userBalance1After == (userBalance1Before + amountOut), "User token1 balance should increase by amount out");

        vm.stopPrank();
    }

    function test_CollectFees() public {
        (uint256 tokenId, , , ) = _createPoolAndMintPosition();
        assertTrue(tokenId > 0, "Token ID be greater than 0");

        vm.startPrank(user);
        token0.approve(address(poolMaster), type(uint256).max);
        token1.approve(address(poolMaster), type(uint256).max);
        poolMaster.swapExactInputSingle(SWAP_AMOUNT, 0, true); // token0 -> token1
        poolMaster.swapExactInputSingle(SWAP_AMOUNT, 0, false); // token1 -> token0
        vm.stopPrank();

        vm.prank(owner);
        uint256 balance0Before = token0.balanceOf(address(poolMaster));
        uint256 balance1Before = token1.balanceOf(address(poolMaster));

        poolMaster.collectFeesFromPosition(0);

        uint256 balance0After = token0.balanceOf(address(poolMaster));
        uint256 balance1After = token1.balanceOf(address(poolMaster));

        assertGe(balance0After, balance0Before, "Token0 balance should increase or stay same after collecting fees");
        assertGe(balance1After, balance1Before, "Token1 balance should increase or stay same after collecting fees");
        assertTrue(balance0After > balance0Before || balance1After > balance1Before, "At least one token balance should increase");
    }

    // ===============================================================
    // Тесты вспомогательных функций (rescue)
    // ===============================================================

    function test_Rescue() public {
        // Отправляем ETH и токены на контракт "случайно"
        vm.deal(address(poolMaster), 1 ether);
        vm.startPrank(owner);
        token0.transfer(address(poolMaster), 100 ether);

        uint256 ownerEthBefore = owner.balance;
        uint256 ownerToken0Before = token0.balanceOf(owner);

        // Владелец "спасает" средства
        poolMaster.rescue(payable(owner), 1 ether);
        poolMaster.rescueToken(owner, address(token0), 100 ether);
        vm.stopPrank();

        assertEq(owner.balance, ownerEthBefore + 1 ether, "Owner should receive rescued ETH");
        assertEq(token0.balanceOf(owner), ownerToken0Before + 100 ether, "Owner should receive rescued tokens");
    }

    // ===============================================================
    // Вспомогательная внутренняя функция
    // ===============================================================

    function _createPoolAndMintPosition() internal returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        vm.prank(owner);
        uint160 initialSqrtPriceX96 = TickMath.getSqrtRatioAtTick(0);
        poolMaster.createPool(address(token0), address(token1), POOL_FEE, TICK_SPACING, initialSqrtPriceX96);

        vm.startPrank(owner);
        token0.transfer(address(poolMaster), INITIAL_LIQUIDITY_AMOUNT);
        token1.transfer(address(poolMaster), INITIAL_LIQUIDITY_AMOUNT);

        int24 lowerTick = -TICK_SPACING * 100;
        int24 upperTick = TICK_SPACING * 100;

        (tokenId, liquidity, amount0, amount1) = poolMaster.mintPosition(
            lowerTick,
            upperTick,
            INITIAL_LIQUIDITY_AMOUNT,
            INITIAL_LIQUIDITY_AMOUNT
        );
        vm.stopPrank();
    }
}
