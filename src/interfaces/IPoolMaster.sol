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

    function createPool(
        address _token0, address _token1, uint24 _fee, uint160 _sqrtPriceX96
    ) external;

    function rescue(address payable _to, uint256 _amount) external;

    function rescueToken(address _to, address _token, uint256 _amount) external;

    function getPosition(uint256 _id) external view returns (PositionInfo memory);
}
