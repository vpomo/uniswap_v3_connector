// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


interface IPoolMaster is IERC721Receiver {

    struct StakePoolInfo {
        address currentPool;
        uint256 lastTime;
        uint256 unlockTime;
        uint256 poolToken0Amount;
        uint256 poolToken1Amount;
        uint256 liquidityAmount;
        uint256 rewardPaidToken0Amount;
        uint256 rewardPaidToken1Amount;
        uint256 totalToken0Fee;
        uint256 totalToken1Fee;
        uint256 stakeTime;
        uint256 unStakeTime;
        uint256 startStakedliquidity;
        uint256 startTotalToken0Fee;
        uint256 startTotalToken1Fee;
    }

    struct NftInfo {
        uint256 tokenId;
        uint256 unlockTime;
        address currentPool;
        address token0;
        address token1;
        uint256 reward0;
        uint256 reward1;
        uint256 staked0;
        uint256 staked1;
        uint256 liquidity;
        uint256 startStakedliquidity;
        uint256 stakeTime;
        uint256 lastTime;
        uint256 totalToken0Fee;
        uint256 totalToken1Fee;
    }

    struct PoolInfo {
        address token0;
        address token1;
        bool isActive;
        uint256 positionId;
        uint24 fee;
        int24 tickSpacing;
        uint256 currToken0Staked;
        uint256 currToken1Staked;
        uint256 currLiquidityStaked;
        uint256 currToken0Fee;
        uint256 currToken1Fee;
        uint256[] nftIds;
        uint256 totalToken0Fee;
        uint256 totalToken1Fee;
    }

    struct PoolPosition {
        address pool;
        uint256 percent;
    }

    struct PositionByNft {
        address user;
        uint256 positionId;
        uint256 poolToken0Amount;
        uint256 poolToken1Amount;
        uint256 liquidity;
    }

    function getReward(uint256 _nftId) external;

    function getAllReward() external;

    function burnNft(uint256 _nftId) external;

//    function executeSwapExactIn(
//        address _tokenIn,
//        address _tokenOut,
//        uint256 _amountIn,
//        uint256 _amountOutMin
//    ) external payable;

//    function executeSwapExactOut(
//        address _tokenIn,
//        address _tokenOut,
//        uint256 _amountOut,
//        uint256 _amountInMax
//    ) external payable;

//    function collectAllFees() external;

    function addMinter(address user) external;

    function removeMinter(address user) external;

    function createSomePool(
        address _token0, address _token1, uint24 _fee, uint160 _sqrtPriceX96
    ) external;

//    function mintPosition(
//        uint256 _amount0ToAdd,
//        uint256 _amount1ToAdd,
//        int24 _lowerTick,
//        int24 _upperTick
//    ) external returns (
//        uint256 tokenId,
//        uint128 liquidity,
//        uint256 amount0,
//        uint256 amount1
//    );

//    function increaseLiquidityCurrentRange(uint256 _amount0ToAdd, uint256 _amount1ToAdd) external returns (
//        uint128 liquidity, uint256 amount0, uint256 amount1
//    );
//
//    function decreaseLiquidityCurrentRange(uint128 _liquidity) external returns (
//        uint256 amount0, uint256 amount1
//    );

//    function changeRange(
//        uint160 _sqrtPriceLimitX96,
//        uint256 _amount0ToAdd,
//        uint256 _amount1ToAdd,
//        int24 _lowerTick,
//        int24 _upperTick
//    ) external;

//    function burnPosition() external;

    function rescue(address payable _to, uint256 _amount) external;

    function rescueToken(address _to, address _token, uint256 _amount) external;

    function updateOracleContract(address _primeOracle) external;

    function setIterationVars(uint256 _newMaxIterations, uint256 _minPercent) external;

    function calcRewardFromLiquidity(
        uint256 _nftId
    ) external view returns (uint256 rewardAmount0, uint256 rewardAmount1);

    function userInfo(address _user) external view returns (NftInfo[] memory);

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external returns (bytes4);

//    function totalToken0Fee() external view returns(uint256);
//
//    function totalToken1Fee() external view returns(uint256);
//
//    function currToken0Fee() external view returns(uint256);
//
//    function currToken1Fee() external view returns(uint256);
//
//    function currToken0Staked() external view returns(uint256);
//
//    function currToken1Staked() external view returns(uint256);
//
//    function currLiquidityStaked() external view returns(uint256);
}
