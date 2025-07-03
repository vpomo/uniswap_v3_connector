// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "./interfaces/INonfungiblePositionManager.sol";
import "./interfaces/IPermit2.sol";
import "./interfaces/IPoolInitializer.sol";

import "./interfaces/IPoolMaster.sol";
import "./interfaces/IPrimeOracle.sol";
import "./interfaces/ITicketNft.sol";
import "./interfaces/IUniswapV3PoolState.sol";
import "./interfaces/IUniversalRouter.sol";
import "./interfaces/IV3PoolActions.sol";
import "./interfaces/IV3PoolImmutables.sol";
import "./libraries/TransferHelper.sol";
import {IUniswapV3Pool} from "../lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";


contract PoolMaster is OwnableUpgradeable, ReentrancyGuardUpgradeable, IPoolMaster, UUPSUpgradeable {
    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = -MIN_TICK;
    int24 private constant TICK_SPACING = 200;

    uint256 private constant MULTIPLIER = 1 ether;
    uint256 private constant DELAY = 100;

    uint8 private constant V3_SWAP_EXACT_IN = 0x00;
    uint8 private constant V3_SWAP_EXACT_OUT = 0x01;

    INonfungiblePositionManager public nonfungiblePositionManager;
    IUniversalRouter public universalRouter;
    address public permit2; //0x000000000022D473030F116dDEE9F6B43aC78BA3

    address public token0;
    address public token1;
    uint24 public fee;
    IUniswapV3Pool public pool;

    event Rescue(address indexed to, uint amount);
    event RescueToken(address indexed token, address indexed to, uint amount);

    event OnERC721Received(address operator, address from, uint256 tokenId, bytes data);
    event MintCallback(uint256 amount0, uint256 amount1, bytes data);
    event PoolLiquidityStaked(
        address indexed user, address indexed pool, uint256 nftId, uint256 token0amount, uint256 token1amount, uint256 liquidityAmount
    );
    event PoolLiquidityUnStaked(
        address indexed user, address indexed pool, uint256 nftId,
        uint256 token0amount, uint256 token1amount, uint256 liquidityAmount
    );
    event MintPosition(
        address indexed sender, address token0, address token1,
        uint256 amount0, uint256 amount1, uint128 liquidity,
        int24 lowerTick, int24 upperTick, uint256 tokenId
    );
    event BurnPosition(address indexed sender, address indexed pool, uint256 tokenId);
    event ChangeRange(
        address indexed sender, address indexed pool, uint160 sqrtPriceLimitX96,
        uint256 amount0, uint256 amount1,
        int24 lowerTick,int24 upperTick
    );
    event CollectAllFees(address indexed pool, uint256 tokenId, uint256 feeAmount0, uint256 feeAmount1);
    event CreateSomePool(
        address indexed sender, address token0, address token1,
        uint24 fee, uint160 sqrtPriceLimitX96, address pool
    );
    event UpdateOracleContract(address sender, address oldContract, address newContract);
    event RenounceOwnership(address user);

    event AddMinter(address indexed operator, address user);
    event RemoveMinter(address indexed operator, address user);
    event AddWhiteListPool(address indexed operator, address user);
    event RemoveWhiteListPool(address indexed operator, address user);
    event SetIterationVars(address indexed operator, uint256 newMaxIterations, uint256 mewMinPercent);
    event LogAmounts(uint256 amount0, uint256 amount1);

    function initialize(
        address _owner,
        address _nonfungiblePositionManager,
        address _universalRouter,
        address _permit2
    ) public initializer {
        _checkZeroAddress(_owner);
        _checkZeroAddress(_nonfungiblePositionManager);
        _checkZeroAddress(_universalRouter);
        _checkZeroAddress(_permit2);

        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        universalRouter = IUniversalRouter(_universalRouter);
        permit2 = _permit2;
    }

    receive() external payable {
    }

    function createPool(
        address _token0, address _token1, uint24 _fee, uint160 _sqrtPriceX96
    ) external override onlyOwner {
        _checkZeroAddress(_token0);
        _checkZeroAddress(_token1);
        _checkZeroAmount(_sqrtPriceX96);
        require(_token0 < _token1, "PoolMaster: wrong order of tokens");
        address poolAddress = IPoolInitializer(address(nonfungiblePositionManager)).createAndInitializePoolIfNecessary(
            _token0,
            _token1,
            _fee,
            _sqrtPriceX96
        );
        _checkZeroAddress(poolAddress);
        pool = IUniswapV3Pool(poolAddress);
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        emit CreatePool(msg.sender, _token0, _token1, _fee, _sqrtPriceX96, poolAddress);
    }

    /// ===============================================================
    /// writing area for anybody
    /// ===============================================================

    function swapExactInputSingle(
        uint256 _amountIn,
        uint256 _minAmountOut,
        bool _zeroForOne
    ) public payable nonReentrant returns(uint256 amountOut) {
        address poolToken0 = _zeroForOne ? token0 : token1;
        address poolToken1 = _zeroForOne ? token1 : token0;
        TransferHelper.safeTransferFrom(poolToken0, msg.sender, address(this), _amountIn);
        return _executeSwapExactIn(poolToken0, poolToken1, fee, _amountIn, _minAmountOut, msg.sender);
    }

    function collectPoolAllFees(address _pool) public {
        PoolData storage data = _poolData[_pool];
        (uint256 feeAmount0, uint256 feeAmount1) = _collectPoolAllFees(_pool);
        data.currToken0Fee += feeAmount0;
        data.currToken1Fee += feeAmount1;
        data.totalToken0Fee += feeAmount0;
        data.totalToken1Fee += feeAmount1;
    }

    /// ===============================================================
    /// owner's writing area
    /// ===============================================================

    function mintPoolPosition(
        address _pool,
        uint256 _amount0ToAdd,
        uint256 _amount1ToAdd,
        int24 _lowerTick,
        int24 _upperTick
    ) external onlyOwner returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    ) {
        PoolInfo memory info = getPoolInfo(_pool);
        require(info.isActive, "PoolMaster: pool isn't active");

        _prepareApprove(info.token0, info.token1, _amount0ToAdd, _amount1ToAdd);
        (tokenId, liquidity, amount0, amount1) = _mintPosition(
                info.token0, info.token1, info.fee,
                _amount0ToAdd, _amount1ToAdd, _lowerTick, _upperTick,
                address(this), info.tickSpacing
        );
        PoolData storage data = _poolData[_pool];
        data.currentTokenId = tokenId;
        _resetApprove(info.token0, info.token1);
    }

    function increasePoolLiquidityCurrentRange(
        address _pool,
        uint256 _amount0ToAdd,
        uint256 _amount1ToAdd
    ) public onlyOwnerOrThisContract returns (
        uint128 liquidity, uint256 amount0, uint256 amount1
    ) {
        _checkAvailableBalance(_pool, _amount0ToAdd, _amount1ToAdd);
        PoolInfo memory info = getPoolInfo(_pool);

        _prepareApprove(info.token0, info.token1, _amount0ToAdd, _amount1ToAdd);
        uint256 positionId = _poolData[_pool].currentTokenId;
        (liquidity, amount0, amount1) = _increasePoolLiquidityCurrentRange(positionId, _amount0ToAdd, _amount1ToAdd);
        _resetApprove(info.token0, info.token1);
    }

    function decreasePoolLiquidityCurrentRange(address _pool, uint128 _liquidity) public onlyOwner returns (
        uint256 amount0, uint256 amount1
    ) {
        (amount0, amount1) = _decreasePoolLiquidityCurrentRange(_pool, _liquidity);
        _collectPoolAllFees(_pool);
    }

    function changeRange(
        address _pool,
        uint160 _sqrtPriceLimitX96,
        uint256 _amount0ToAdd,
        uint256 _amount1ToAdd,
        int24 _lowerTick,
        int24 _upperTick
    ) external onlyOwner {
        PoolInfo memory info = getPoolInfo(_pool);
        _checkTicks(_lowerTick, _upperTick, info.tickSpacing);
        burnPosition(_pool);
        _checkAvailableBalance(_pool, _amount0ToAdd, _amount1ToAdd);
        PoolData storage data = _poolData[_pool];


        _prepareApprove(info.token0, info.token1, _amount0ToAdd, _amount1ToAdd);
        require(data.currentTokenId == 0, 'PoolMaster: the position already exists');
        (uint256 tokenId, , uint256 amount0, uint256 amount1) = _mintPosition(
                info.token0, info.token1, info.fee, _amount0ToAdd, _amount1ToAdd,
                _lowerTick, _upperTick, address(this), info.tickSpacing
        );
        data.currentTokenId = tokenId;
        _resetApprove(info.token0, info.token1);
        emit ChangeRange(msg.sender, _pool, _sqrtPriceLimitX96, amount0, amount1, _lowerTick, _upperTick);
    }

    function burnPosition(address _pool) public onlyOwnerOrThisContract {
        PoolData storage data = _poolData[_pool];
        uint256 positionId = data.currentTokenId;
        ( , , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(positionId);
        collectPoolAllFees(_pool);
        _decreasePoolLiquidityCurrentRange(_pool, liquidity);
        collectPoolAllFees(_pool);
        nonfungiblePositionManager.burn(positionId);
        emit BurnPosition(msg.sender, _pool, positionId);
        data.currentTokenId = 0;
    }

    function rescue(address payable _to, uint256 _amount) external override onlyOwner {
        _checkZeroAddress(_to);
        _checkZeroAmount(_amount);
        TransferHelper.safeTransferBNB(_to, _amount);
        emit Rescue(_to, _amount);
    }

    function rescueToken(address _to, address _token, uint256 _amount) external override onlyOwner {
        _checkZeroAddress(_to);
        _checkZeroAmount(_amount);
        TransferHelper.safeTransfer(_token, _to, _amount);
        emit RescueToken(_token, _to, _amount);
    }

    /// ===============================================================
    /// reading area
    /// ===============================================================

    /// ===============================================================
    /// internal and private area
    /// ===============================================================

    function _checkAvailableBalance(address _pool, uint256 _amount0ToAdd, uint256 _amount1ToAdd) private view {
        PoolInfo memory info = getPoolInfo(_pool);
        uint256 balance0 = IERC20(info.token0).balanceOf(address(this));
        uint256 balance1 = IERC20(info.token1).balanceOf(address(this));
        PoolData storage data = _poolData[_pool];

        require(data.currToken0Fee < balance0, "PoolMaster: incorrect available amount for token0's fee");
        require(data.currToken1Fee < balance1, "PoolMaster: incorrect available amount for token1's fee");

        uint256 available0 = balance0 - data.currToken0Fee;
        uint256 available1 = balance1 - data.currToken1Fee;
        if (available0 < _amount0ToAdd) {
            revert(string(abi.encodePacked(
                    "PoolMaster: not enough available amount for token0: ",
                    _uint256ToString(_amount0ToAdd - available0)))
            );
        }
        if (available1 < _amount1ToAdd) {
            revert(string(abi.encodePacked(
                    "PoolMaster: not enough available amount for token1: ",
                    _uint256ToString(_amount1ToAdd - available1)))
            );
        }
    }

    function _checkZeroAddress(address _value) private pure {
        require(_value != address(0), 'PoolMaster: can not be zero address');
    }

    function _checkZeroAmount(uint256 _value) private pure {
        require(_value > 0, 'PoolMaster: should be greater than 0');
    }

    function _checkTicks(int24 _lowerTick, int24 _upperTick, int24 _tickSpacing) private pure returns(int24 low, int24 upper){
        require(_lowerTick < _upperTick, 'PoolMaster: wrong tick order');
        require(_lowerTick >= MIN_TICK && _lowerTick < MAX_TICK, 'PoolMaster: wrong lower tick');
        require(_upperTick <= MAX_TICK && _upperTick > MIN_TICK, 'PoolMaster: wrong upper tick');
        low = (_lowerTick / _tickSpacing) * _tickSpacing;
        upper = (_upperTick / _tickSpacing) * _tickSpacing;
    }

    function _sortPoolTokens(address _token0, address _token1) private pure returns(
        address poolToken0, address poolToken1
    ) {
        return _token0 > _token1 ? (_token1, _token0):(_token0, _token1);
    }

    function _resetApprove(address _token0, address _token1) private {
        TransferHelper.safeApprove(_token0, address(nonfungiblePositionManager), 0);
        TransferHelper.safeApprove(_token1, address(nonfungiblePositionManager), 0);
    }

    function _prepareApprove(address _token0, address _token1, uint256 _amount0ToAdd, uint256 _amount1ToAdd) private {
        TransferHelper.safeApprove(_token0, address(nonfungiblePositionManager), _amount0ToAdd);
        TransferHelper.safeApprove(_token1, address(nonfungiblePositionManager), _amount1ToAdd);
    }

    function _prepareApproveForPM(
        address _token0, address _token1, uint256 _amount0ToAdd, uint256 _amount1ToAdd, address _pm
    ) private {
        TransferHelper.safeApprove(_token0, _pm, _amount0ToAdd);
        TransferHelper.safeApprove(_token1, _pm, _amount1ToAdd);
    }

    function _prepareTokens(address _token0, address _token1, uint256 _amount0ToAdd, uint256 _amount1ToAdd) private {
        if (_amount0ToAdd > 0) {
            TransferHelper.safeTransferFrom(_token0, msg.sender, address(this), _amount0ToAdd);
        }
        if (_amount1ToAdd > 0) {
            TransferHelper.safeTransferFrom(_token1, msg.sender, address(this), _amount1ToAdd);
        }
    }

    function _executeSwapExactIn(
        address _tokenIn,
        address _tokenOut,
        uint24 _poolFee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _recipient
    ) private returns(uint256 amountOut) {
        uint256 beforeAmountOut = IERC20(_tokenOut).balanceOf(address(this));
        uint256 deadline = block.timestamp + 60;
        IPermit2(permit2).approve(_tokenIn, address(universalRouter), uint160(_amountIn), uint48(deadline));
        TransferHelper.safeApprove(_tokenIn, permit2, _amountIn);

        bytes memory commands = abi.encodePacked(
            bytes1(V3_SWAP_EXACT_IN)
        );
        bytes memory path = abi.encodePacked(_tokenIn, _poolFee, _tokenOut);
        bytes memory input0 = abi.encode(
            _recipient,
            _amountIn,
            _amountOutMin,
            path,
            true
        );
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = input0;

        universalRouter.execute{value: 0}(commands, inputs, deadline);
        uint256 afterAmountOut = IERC20(_tokenOut).balanceOf(address(this));
        return afterAmountOut - beforeAmountOut;
    }

    function _collectPoolAllFees(address _pool) private returns (uint256 feeAmount0, uint256 feeAmount1) {
        PoolData storage data = _poolData[_pool];
        uint256 positionId = data.currentTokenId;

        INonfungiblePositionManager.CollectParams memory params =
        INonfungiblePositionManager.CollectParams({
        tokenId: positionId,
        recipient: address(this),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
        });

        (feeAmount0, feeAmount1) = nonfungiblePositionManager.collect(params);
        data.lastCollectFees = block.timestamp;
        emit CollectAllFees(_pool, positionId, feeAmount0, feeAmount1);
    }

    function _mintPosition(
        address _token0,
        address _token1,
        uint24 _fee,
        uint256 _amount0ToAdd,
        uint256 _amount1ToAdd,
        int24 _lowerTick,
        int24 _upperTick,
        address _recipient,
        int24 _tickSpacing
    ) private returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    ) {
        (int24 lowerTick, int24 upperTick) = _checkTicks(_lowerTick, _upperTick, _tickSpacing);
        require(_token0 < _token1, "PoolMaster: incorrect token order");

        INonfungiblePositionManager.MintParams memory params =
        INonfungiblePositionManager.MintParams({
                token0: _token0,
                token1: _token1,
                fee: _fee,
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: _amount0ToAdd,
                amount1Desired: _amount1ToAdd,
                amount0Min: 0,
                amount1Min: 0,
                recipient: _recipient,
                deadline: block.timestamp + DELAY
        });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);
        emit MintPosition(msg.sender, _token0, _token1, amount0, amount1, liquidity, _lowerTick, _upperTick, tokenId);
    }

    function _increasePoolLiquidityCurrentRange(
        uint256 _currentTokenId,
        uint256 _amount0ToAdd,
        uint256 _amount1ToAdd
    ) private returns (
        uint128 liquidity, uint256 amount0, uint256 amount1
    ) {

        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
        INonfungiblePositionManager.IncreaseLiquidityParams({
        tokenId: _currentTokenId,
        amount0Desired: _amount0ToAdd,
        amount1Desired: _amount1ToAdd,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp + DELAY
        });
        (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(params);
    }

    function _decreasePoolLiquidityCurrentRange(address _pool, uint128 _liquidity) private returns (
        uint256 amount0, uint256 amount1
    ) {
        uint256 positionId = _poolData[_pool].currentTokenId;
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
        INonfungiblePositionManager.DecreaseLiquidityParams({
        tokenId: positionId,
        liquidity: _liquidity,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp + DELAY
        });
        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);
    }

    function _getPoolPrice(address _pool) private view returns(uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3PoolState(_pool).slot0();
        return uint256(sqrtPriceX96)*(uint256(sqrtPriceX96)) * MULTIPLIER >> (96 * 2);
    }

    function _checkPositions(PoolPosition[] memory _positions) private view {
        uint256 len = _positions.length;
        require(len > 0, "PoolMaster: wrong positions length");
        uint256 allPercent = 0;
        for (uint256 i = 0; i < len; i++) {
            address currPool = _positions[i].pool;
            uint256 currPercent = _positions[i].percent;
            require(whiteListPools.contains(currPool), "PoolMaster: pool is not in the whitelist");
            require(currPercent <= 100 && currPercent > 0, "PoolMaster: wrong percent");
            allPercent += _positions[i].percent;
        }
        require(allPercent == 100, "PoolMaster: wrong sum percents");
    }

    function _uint256ToString(uint256 _number) private pure returns (string memory) {
        if (_number == 0) {
            return "0";
        }

        uint256 temp = _number;
        uint256 digits = 0;

        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        temp = _number;

        while (temp != 0) {
            digits = digits - 1;
            buffer[digits] = bytes1(uint8(48 + temp % 10));
            temp /= 10;
        }

        return string(buffer);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
