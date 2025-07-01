// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IPrimeOracle {

    function getEquivalentAmount(
        uint256 _amount, address _token0, address _token1
    ) external view returns (uint256);
}
