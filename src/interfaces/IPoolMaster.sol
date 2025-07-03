// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


interface IPoolMaster is IERC721Receiver {

    struct PositionInfo {
        uint256 tokenId;
        int24 lowTick;
        int24 upperTick;
    }

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

}
