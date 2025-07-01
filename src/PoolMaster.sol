// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./libraries/TransferHelper.sol";
import "./interfaces/IPoolMaster.sol";
import "./interfaces/IPermit2.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import "./interfaces/IPoolInitializer.sol";
import "./interfaces/IV3PoolActions.sol";
import "./interfaces/IUniswapV3PoolState.sol";
import "./interfaces/IV3PoolImmutables.sol";
import "./interfaces/IPrimeOracle.sol";
import "./interfaces/ITicketNft.sol";
import "./interfaces/IUniversalRouter.sol";


contract PoolMaster is OwnableUpgradeable, ReentrancyGuardUpgradeable, IPoolMaster, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    EnumerableSet.AddressSet private whiteListPools;

    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = -MIN_TICK;
    int24 private constant TICK_SPACING = 200;

    uint256 private constant MULTIPLIER = 1 ether;
    uint256 private constant DELAY = 100;

    uint8 private constant V3_SWAP_EXACT_IN = 0x00;
    uint8 private constant V3_SWAP_EXACT_OUT = 0x01;

    address public USDT = 0x55d398326f99059fF775485246999027B3197955;
    address public WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    INonfungiblePositionManager public nonfungiblePositionManager;
    IUniversalRouter public universalRouter;
    IPrimeOracle public primeOracle;
    ITicketNft public ticketNft;

    address public permit2; //0x000000000022D473030F116dDEE9F6B43aC78BA3

    mapping(uint256 => PoolInfo) public poolInfos;

    //pool -> nft ID -> StakePoolInfo
    mapping(uint256 => StakePoolInfo) public poolStakeInfos;
    mapping(uint256 => PositionByNft) public positionByNfts;

    mapping(address => bool) private _minters;
    // nft ID -> pool
    mapping(uint256 => address) private _actualPool;
    // pool ->
    mapping(address => PoolData) private _poolData;

    uint256 public maxIterations;
    uint256 public minPercent;

    struct PoolData {
        uint256 startTime;
        uint256 deActivationTime;
        uint256 currentTokenId;
        uint256 lastCollectFees;

        uint256 currToken0Staked;
        uint256 currToken1Staked;
        uint256 currLiquidityStaked;

        uint256 totalToken0Fee;
        uint256 totalToken1Fee;
        uint256 currToken0Fee;
        uint256 currToken1Fee;

        address swapToken;
        bytes[] toUSDTSwapPath;
        bytes[] fromUSDTSwapPath;
        EnumerableSet.UintSet nftIds;
    }

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
    event AddPoolData(address indexed operator, address user);
    event SetIterationVars(address indexed operator, uint256 newMaxIterations, uint256 mewMinPercent);
    event LogAmounts(uint256 amount0, uint256 amount1);

    modifier onlyMinter() {
        address sender = msg.sender;
        require(_minters[sender] || sender == owner(), "PoolMaster: wrong minter");
        _;
    }

    modifier onlyOwnerOrThisContract() {
        require(msg.sender == address(this) || msg.sender == owner(), "PoolMaster: not an allowed user");
        _;
    }

    function initialize(
        address _owner,
        address _nonfungiblePositionManager,
        address _universalRouter,
        address _permit2,
        address _ticketNft
    ) public initializer {
        _checkZeroAddress(_owner);
        _checkZeroAddress(_nonfungiblePositionManager);
        _checkZeroAddress(_universalRouter);
        _checkZeroAddress(_permit2);
        _checkZeroAddress(_ticketNft);

        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        universalRouter = IUniversalRouter(_universalRouter);
        permit2 = _permit2;
        ticketNft = ITicketNft(_ticketNft);

        maxIterations = 5;
        minPercent = 0;
    }

    receive() external payable {
    }

    /// ===============================================================
    /// staking contract's writing area
    /// ===============================================================

    function mintNft(
        address _user, uint256 _stakeAmount, PoolPosition[] memory _positions
    ) external onlyMinter {
        _checkPositions(_positions);
        TransferHelper.safeTransferFrom(USDT, msg.sender, address(this), _stakeAmount);
        uint256 currTime = block.timestamp;
        uint256 len = _positions.length;
        require(len < 6, 'PoolMaster: wrong number of pools');

        for(uint256 i = 0; i < len; i++) {
            address currPool = _positions[i].pool;
            uint256 currAmount = _stakeAmount * _positions[i].percent / 100;

            collectPoolAllFees(currPool);
            PoolData storage data = _poolData[currPool];
            (uint256 liquidity, uint256 amount0, uint256 amount1) = _stakeToPoolLiquidity(
                currPool, data.currentTokenId, currAmount
            );

            uint256 nftId = ticketNft.mint(_user);
            require(nftId > 0, 'PoolMaster: token id should be greater than zero');
            StakePoolInfo storage stakeInfo = poolStakeInfos[nftId];
            stakeInfo.currentPool = currPool;
            stakeInfo.unlockTime = currTime; // Set end time
            stakeInfo.lastTime = currTime;
            stakeInfo.stakeTime = currTime;
            stakeInfo.poolToken0Amount = amount0;
            stakeInfo.poolToken1Amount = amount1;
            stakeInfo.liquidityAmount = liquidity;
            stakeInfo.totalToken0Fee = data.totalToken0Fee;
            stakeInfo.totalToken1Fee = data.totalToken1Fee;
            stakeInfo.startTotalToken0Fee = data.totalToken0Fee;
            stakeInfo.startTotalToken1Fee = data.totalToken1Fee;
            stakeInfo.startStakedliquidity = data.currLiquidityStaked;
            data.nftIds.add(nftId);
            emit PoolLiquidityStaked(_user, currPool, nftId, amount0, amount1, liquidity);
        }
    }

    function getReward(uint256 _nftId) public override {
        _checkNftOwner(_nftId);
        _getReward(_nftId, msg.sender);
    }

    function getAllReward() public override {
        address sender = msg.sender;
        uint256[] memory tokenIds = ticketNft.tokensOfOwner(sender);
        uint256 len = tokenIds.length;
        for(uint256 i = 0; i < len; i++) {
            _getReward(tokenIds[i], sender);
        }
    }

    function burnNft(uint256 _nftId) external override {
        _checkNftOwner(_nftId);
        StakePoolInfo storage stakeInfo = poolStakeInfos[_nftId];
        require(stakeInfo.unlockTime <= block.timestamp, 'PoolMaster: wrong unlock time');

        address sender = msg.sender;
        _getReward(_nftId, sender);
        require(ticketNft.burn(_nftId), 'PoolMaster: wrong burning');

        uint256 liquidityAmount = stakeInfo.liquidityAmount;
        stakeInfo.liquidityAmount = 0;
        stakeInfo.poolToken0Amount = 0;
        stakeInfo.poolToken1Amount = 0;
        address currentPool = stakeInfo.currentPool;
        (uint256 amount0, uint256 amount1) = _unStakeFromLiquidity(currentPool, liquidityAmount);
        emit PoolLiquidityUnStaked(sender, currentPool, _nftId, amount0, amount1, liquidityAmount);

        PoolInfo memory info = getPoolInfo(currentPool);
        PositionByNft storage position = positionByNfts[_nftId];
        _prepareApprove(info.token0, info.token1, amount0, amount1);
        ( , , , , , int24 tickLower, int24 tickUpper, , , , , ) = nonfungiblePositionManager.positions(
            _poolData[currentPool].currentTokenId
        );

        PoolInfo memory poolInfo = getPoolInfo(currentPool);
        (uint256 tokenId, uint256 liquidity, uint256 amount0Added, uint256 amount1Added) = _mintPosition(
            info.token0, info.token1, info.fee, amount0, amount1, tickLower, tickUpper, sender, poolInfo.tickSpacing
        );
        position.user = sender;
        position.positionId = tokenId;
        position.poolToken0Amount = amount0Added;
        position.poolToken1Amount = amount1Added;
        position.liquidity = liquidity;
    }

    /// ===============================================================
    /// writing area for anybody
    /// ===============================================================
    function executePoolSwapExactIn(
        address _pool,
        uint256 _amountIn,
        bool _notReverse
    ) public payable nonReentrant returns(uint256 amountOut) {
        PoolInfo memory info = getPoolInfo(_pool);
        address tokenIn = _notReverse ? info.token0 : info.token1;
        address tokenOut = _notReverse ? info.token1 : info.token0;
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), _amountIn);
        return _executeSwapExactIn(tokenIn, tokenOut, info.fee, _amountIn, 0, msg.sender);
    }

    function executeSwapExactIn(
        address _tokenIn,
        address _tokenOut,
        uint24 _poolFee,
        uint256 _amountIn,
        uint256 _amountOutMin
    ) public payable nonReentrant returns(uint256 amountOut) {
        TransferHelper.safeTransferFrom(_tokenIn, msg.sender, address(this), _amountIn);
        return _executeSwapExactIn(_tokenIn, _tokenOut, _poolFee, _amountIn, _amountOutMin, msg.sender);
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

    function addMinter(address user) external override onlyOwner {
        require(user != address(0), "PoolMaster: wrong address");
        require(!_minters[user], "PoolMaster: user is already minter");
        _minters[user] = true;
        emit AddMinter(msg.sender, user);
    }

    function removeMinter(address user) external override onlyOwner {
        require(_minters[user], "PoolMaster: user is not minter");
        _minters[user] = false;
        emit RemoveMinter(msg.sender, user);
    }

    function addWhiteListPool(address _pool) external onlyOwner {
        require(_pool != address(0), "PoolMaster: wrong address");
        require(whiteListPools.add(_pool), "PoolMaster: operation is failed");
        emit AddWhiteListPool(msg.sender, _pool);
    }

    function removeWhiteListPool(address _pool) external onlyOwner {
        require(whiteListPools.contains(_pool), "PoolMaster: wrong pool address");
        require(whiteListPools.remove(_pool), "PoolMaster: operation is failed");
        emit RemoveWhiteListPool(msg.sender, _pool);
    }

    function addPoolData(
        address _pool,
        address _swapToken,
        bytes[] calldata _toUSDTSwapPath,
        bytes[] calldata _fromUSDTSwapPath
    ) external onlyOwner {
        require(_swapToken != address(0), "PoolMaster: wrong address");
        require(whiteListPools.contains(_pool), "PoolMaster: the pool is not exist on the white list");
        PoolData storage data = _poolData[_pool];
        data.startTime = block.timestamp;
        data.swapToken = _swapToken;
        data.toUSDTSwapPath = _toUSDTSwapPath;
        data.fromUSDTSwapPath = _fromUSDTSwapPath;

        emit AddPoolData(msg.sender, _pool);
    }

    function createSomePool(
        address _token0, address _token1, uint24 _fee, uint160 _sqrtPriceX96
    ) external override onlyOwner {
        _checkZeroAmount(_sqrtPriceX96);
        (address poolToken0, address poolToken1) = _sortPoolTokens(_token0, _token1);
        address createdPool = IPoolInitializer(address(nonfungiblePositionManager)).createAndInitializePoolIfNecessary(
            poolToken0,
            poolToken1,
            _fee,
            _sqrtPriceX96
        );
        _checkZeroAddress(createdPool);
        emit CreateSomePool(msg.sender, _token0, _token1, _fee, _sqrtPriceX96, createdPool);
    }

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

    function updateOracleContract(address _primeOracle) external override onlyOwner {
        _checkZeroAddress(_primeOracle);
        emit UpdateOracleContract(msg.sender, address(primeOracle), _primeOracle);
        primeOracle = IPrimeOracle(_primeOracle);
    }

    function renounceOwnership() public override onlyOwner {
        emit RenounceOwnership(msg.sender);
        revert("PoolMaster: This feature is not available");
    }

    function setIterationVars(uint256 _newMaxIterations, uint256 _minPercent) external override onlyOwner {
        maxIterations = _newMaxIterations;
        minPercent = _minPercent;
        emit SetIterationVars(msg.sender, _newMaxIterations, _minPercent);
    }

    /// ===============================================================
    /// callback area
    /// ===============================================================

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external override returns (bytes4) {
        emit OnERC721Received(_operator, _from, _tokenId, _data);
        return IERC721Receiver.onERC721Received.selector;
    }

    /// ===============================================================
    /// reading area
    /// ===============================================================

    function calcRewardFromLiquidity(uint256 _nftId) public view returns (
        uint256 rewardAmount0, uint256 rewardAmount1
    ) {
        StakePoolInfo memory nftInfo = poolStakeInfos[_nftId];
        address currentPool = nftInfo.currentPool;
        PoolInfo memory poolInfo = getPoolInfo(currentPool);
        PoolData storage data = _poolData[currentPool];

        uint256[] memory nftIds = poolInfo.nftIds;
        uint256 nftTotalCount = nftIds.length;

        if (nftTotalCount > 0) {
            require(_nftId <= ticketNft.tokensCount(), 'PoolMaster: wrong NFT id');
            uint256 allStakedLiquidity = 0;
            uint256 index = 0;
            while (index < nftTotalCount) {
                if (nftIds[index] == _nftId) {
                    nftInfo = poolStakeInfos[_nftId];
                    break;
                } else {
                    index++;
                }
            }
            nftTotalCount--;

            while(index <= nftTotalCount) {
                StakePoolInfo memory beforeInfo = poolStakeInfos[nftIds[index]];
                uint256 diff0 = 0;
                uint256 diff1 = 0;

                if (index < nftTotalCount) {
                    StakePoolInfo memory nextInfo = poolStakeInfos[nftIds[index+1]];
                    if (nftInfo.lastTime < nextInfo.stakeTime) {
                        diff0 = nextInfo.startTotalToken0Fee - beforeInfo.startTotalToken0Fee;
                        diff1 = nextInfo.startTotalToken1Fee - beforeInfo.startTotalToken1Fee;
                        allStakedLiquidity = beforeInfo.startStakedliquidity;
                    } else {
                        index++;
                        continue;
                    }
                } else {
                    allStakedLiquidity = data.currLiquidityStaked;
                    if (nftInfo.lastTime >= beforeInfo.stakeTime) {
                        diff0 = data.totalToken0Fee - nftInfo.totalToken0Fee;
                        diff1 = data.totalToken1Fee - nftInfo.totalToken1Fee;
                    }
                }

                uint256 userFactor = nftInfo.liquidityAmount * MULTIPLIER / allStakedLiquidity;
                rewardAmount0 += diff0 * userFactor / MULTIPLIER;
                rewardAmount1 += diff1 * userFactor / MULTIPLIER;
                index++;
            }
        }
    }

    function userInfo(address _user) external override view returns (NftInfo[] memory) {
        uint256[] memory tokenIds = ticketNft.tokensOfOwner(_user);
        uint256 len = tokenIds.length;
        NftInfo[] memory info = new NftInfo[](len);
        for(uint256 i=0; i<len; i++) {
            uint256 tokenId = tokenIds[i];
            StakePoolInfo memory stakeInfo = poolStakeInfos[tokenId];
            PoolInfo memory poolInfo = getPoolInfo(stakeInfo.currentPool);
            (uint256 rewardAmount0, uint256 rewardAmount1) = calcRewardFromLiquidity(tokenId);
            info[i].tokenId = tokenId;
            info[i].unlockTime = stakeInfo.unlockTime;
            info[i].reward0 = rewardAmount0;
            info[i].reward1 = rewardAmount1;
            info[i].staked0 = stakeInfo.poolToken0Amount;
            info[i].staked1 = stakeInfo.poolToken1Amount;
            info[i].liquidity = stakeInfo.liquidityAmount;
            info[i].currentPool = stakeInfo.currentPool;
            info[i].token0 = poolInfo.token0;
            info[i].token1 = poolInfo.token1;
            info[i].startStakedliquidity = stakeInfo.startStakedliquidity;
            info[i].stakeTime = stakeInfo.stakeTime;
            info[i].lastTime = stakeInfo.lastTime;
            info[i].totalToken0Fee = stakeInfo.totalToken0Fee;
            info[i].totalToken1Fee = stakeInfo.totalToken1Fee;
        }

        return info;
    }

    function getPoolInfo(address _pool) public view returns (PoolInfo memory info) {
        PoolData storage data = _poolData[_pool];
        info.token0 = IV3PoolImmutables(_pool).token0();
        info.token1 = IV3PoolImmutables(_pool).token1();
        info.fee = IV3PoolImmutables(_pool).fee();
        info.tickSpacing = IV3PoolImmutables(_pool).tickSpacing();

        info.positionId = data.currentTokenId;
        info.isActive = data.deActivationTime == 0;

        info.currToken0Staked = data.currToken0Staked;
        info.currToken1Staked = data.currToken1Staked;
        info.currLiquidityStaked = data.currLiquidityStaked;

        info.currToken0Fee = data.currToken0Fee;
        info.currToken1Fee = data.currToken1Fee;

        info.nftIds = data.nftIds.values();

        info.totalToken0Fee = data.totalToken0Fee;
        info.totalToken1Fee = data.totalToken1Fee;
    }

    function isMinter(address user) public view returns (bool) {
        if (user == owner()) {
            return true;
        }
        return _minters[user];
    }

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

    function _getReward(uint256 _nftId, address _user) private {
        StakePoolInfo storage stakeInfo = poolStakeInfos[_nftId];
        PoolData storage data = _poolData[stakeInfo.currentPool];
        if(data.lastCollectFees < block.timestamp) {
            collectPoolAllFees(stakeInfo.currentPool);
        }

        (uint256 reward0, uint256 reward1) = calcRewardFromLiquidity(_nftId);
        stakeInfo.totalToken0Fee = data.totalToken0Fee;
        stakeInfo.totalToken1Fee = data.totalToken1Fee;
        stakeInfo.rewardPaidToken0Amount += reward0;
        stakeInfo.rewardPaidToken1Amount += reward1;
        stakeInfo.lastTime = block.timestamp;

        _transferToUser(stakeInfo.currentPool, _user, reward0, reward1);

        if (reward0 <= data.currToken0Fee) {
            data.currToken0Fee = data.currToken0Fee - reward0;
        }
        if (reward1 <= data.currToken1Fee) {
            data.currToken1Fee = data.currToken1Fee - reward1;
        }
    }

    function _checkNftOwner(uint256 _nftId) private view {
        require(ticketNft.ownerOf(_nftId) == msg.sender, 'PoolMaster: wrong NFT owner');
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

    function _transferToUser(
        address _pool,
        address _user,
        uint256 _amount0,
        uint256 _amount1
    ) private {
        PoolInfo memory info = getPoolInfo(_pool);
        if (_amount0 > 0) {
            TransferHelper.safeTransfer(info.token0, _user, _amount0);
        }
        if (_amount1 > 0) {
            TransferHelper.safeTransfer(info.token1, _user, _amount1);
        }
    }

    function _refundTokens(
        address _token0,
        address _token1,
        uint256 _amount0ToAdd,
        uint256 _amount1ToAdd,
        uint256 _amount0,
        uint256 _amount1
    ) private {
        if (_amount0 < _amount0ToAdd) {
            TransferHelper.safeTransfer(_token0, msg.sender, _amount0ToAdd - _amount0);
        }
        if (_amount1 < _amount1ToAdd) {
            TransferHelper.safeTransfer(_token1, msg.sender, _amount1ToAdd - _amount1);
        }
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

    function _unStakeFromLiquidity(address _pool, uint256 _liquidity) private returns (
        uint256 amount0, uint256 amount1
    ) {
        (amount0, amount1) = _decreasePoolLiquidityCurrentRange(_pool, uint128(_liquidity));
        _collectPoolAllFees(_pool);
        PoolData storage data = _poolData[_pool];
        if(amount0 <= data.currToken0Staked) {
            data.currToken0Staked -= amount0;
        }
        if(amount1 <= data.currToken1Staked) {
            data.currToken1Staked -= amount1;
        }
        if(_liquidity <= data.currLiquidityStaked) {
            data.currLiquidityStaked -= _liquidity;
        }
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

    function _stakeToPoolLiquidity(address _pool, uint256 _currentPositionId, uint256 usdtAmount) private returns (
        uint256 liquidity, uint256 amount0Added, uint256 amount1Added
    ) {
        PoolInfo memory info = getPoolInfo(_pool);
        (uint256 amount0ForAdd, uint256 amount1ToAdd) = _prepareTokensBeforeStake(_pool, usdtAmount);
        uint256 step = 0;
        uint256 amount0ToAdd = amount0ForAdd;
        _prepareApprove(info.token0, info.token1, amount0ToAdd, amount1ToAdd);

        while (step <= maxIterations) {

            (uint256 liq, uint256 amount0, uint256 amount1) = _increasePoolLiquidityCurrentRange(
                _currentPositionId, amount0ToAdd, amount1ToAdd
            );
            liquidity += liq;
            amount0Added += amount0;
            amount1Added += amount1;
            step++;
            if (amount0Added < amount0ForAdd) {
                uint256 percent = 100 - (100*amount0Added)/amount0ForAdd;
                if (percent <= minPercent) {
                    step = maxIterations + 1;
                }
                amount0ToAdd = amount0ForAdd - amount0Added;
            } else {
                step = maxIterations + 1;
            }
        }

        PoolData storage data = _poolData[_pool];
        data.currToken0Staked += amount0Added;
        data.currToken1Staked += amount1Added;
        data.currLiquidityStaked += liquidity;
        _resetApprove(info.token0, info.token1);
    }

    function _prepareTokensBeforeStake(address _pool, uint256 usdtAmount) private returns (
        uint256 amount0, uint256 amount1
    ) {
        PoolInfo memory info = getPoolInfo(_pool);

        if (info.token0 == USDT && info.token1 != USDT) { // USDT -> tokenX
            amount0 = usdtAmount / 2;
            amount1 = _executeSwapExactIn(USDT, info.token1, info.fee, amount0, 0, address(this));
        }
        if (info.token0 != USDT && info.token1 == USDT) { // tokenX -> USDT
            amount1 = usdtAmount / 2;
            amount0 = _executeSwapExactIn(USDT, info.token0, info.fee, amount1, 0, address(this));
        }
        if (info.token0 == WBNB && info.token1 != WBNB) { // WBNB -> tokenX
            // USDT -> WBNB
            uint256 wbnbAmount = _executeSwapExactIn(USDT, WBNB, 100, usdtAmount, 0, address(this));
            // WBNB -> tokenX
            amount0 = wbnbAmount / 2;
            amount1 = _executeSwapExactIn(WBNB, info.token1, info.fee, amount0, 0, address(this));
        }
        if (info.token0 != WBNB && info.token1 == WBNB) { // tokenX -> WBNB
            // USDT -> WBNB
            uint256 wbnbAmount = _executeSwapExactIn(USDT, WBNB, 100, usdtAmount, 0, address(this));
            // WBNB -> tokenX
            amount1 = wbnbAmount / 2;
            amount0 = _executeSwapExactIn(WBNB, info.token0, info.fee, amount1, 0, address(this));
        }
    }

    function _convertTokensToUSDT(address _pool,  uint256 _amount0, uint256 _amount1) private returns (
        uint256 amount
    ){
        PoolInfo memory info = getPoolInfo(_pool);

        if (info.token0 == USDT && info.token1 != USDT) { // USDT -> tokenX
            amount += _amount0;
            amount += _executeSwapExactIn(info.token1, USDT, info.fee, _amount1, 0, address(this));
        }
        if (info.token0 != USDT && info.token1 == USDT) { // tokenX -> USDT
            amount += _amount1;
            amount += _executeSwapExactIn(info.token0, USDT, info.fee, _amount0, 0, address(this));
        }
        if (info.token0 == WBNB && info.token1 != WBNB) { // tokenX -> WBNB
            // tokenX -> WBNB
            uint256 wbnbAmount = _amount0;
            wbnbAmount += _executeSwapExactIn(info.token1, WBNB, info.fee, _amount1, 0, address(this));
            // WBNB -> USDT
            amount = _executeSwapExactIn(WBNB, USDT, 100, wbnbAmount, 0, address(this));
        }
        if (info.token0 != WBNB && info.token1 == WBNB) { // tokenX -> WBNB
            // tokenX -> WBNB
            uint256 wbnbAmount = _amount1;
            wbnbAmount += _executeSwapExactIn(info.token0, WBNB, info.fee, _amount0, 0, address(this));
            // WBNB -> USDT
            amount = _executeSwapExactIn(WBNB, USDT, 100, wbnbAmount, 0, address(this));
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
