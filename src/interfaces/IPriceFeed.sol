// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;


interface IPriceFeed {
    function queryRate(address sourceTokenAddress, address destTokenAddress) external view returns (
        uint256 rate, uint256 precision
    );
    function wbnbToken() external view returns(address);
}
