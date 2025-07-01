// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockErc20Token is ERC20, Ownable {
    constructor() ERC20("MockToken", "MockToken") Ownable(msg.sender) {
        _mint(msg.sender, 10000000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}