// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UserToken} from "../../src/mock/UserToken.sol";

/**
 * @title DeployUserToken
 * @notice Скрипт для деплоя контракта UserToken с использованием Foundry.
 * @dev Скрипт читает конфигурацию (имя токена, символ, начальное количество, владелец)
 */
contract DeployUserToken is Script {
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(deployerPrivateKey != 0, "PRIVATE_KEY must be set in .env file");

        string memory tokenName = "Token BCTC";
        string memory tokenSymbol = "BCTC";

        uint256 initialSupply = 1_000_000 * (10**18);

        address owner = vm.envAddress("OWNER_ADDRESS");
        if (owner == address(0)) {
            owner = vm.addr(deployerPrivateKey);
        }

        console.log("Deploying UserToken with the following parameters:");
        console.log("  - Name: %s", tokenName);
        console.log("  - Symbol: %s", tokenSymbol);
        console.log("  - Initial Supply (wei): %d", initialSupply);
        console.log("  - Owner: %s", toChecksum(owner));
        console.log("  - Deployer: %s", toChecksum(vm.addr(deployerPrivateKey)));

        vm.startBroadcast(deployerPrivateKey);

        UserToken token = new UserToken(
            tokenName,
            tokenSymbol,
            initialSupply,
            owner
        );

        vm.stopBroadcast();

        console.log("UserToken deployed successfully!");
        console.log("Address: %s", address(token));
        return address(token);
    }

    /**
     * @dev Вспомогательная функция для преобразования адреса в checksum-формат для красивого вывода.
     */
    function toChecksum(address addr) private pure returns (string memory) {
        return vm.toString(addr);
    }
}

//sudo env "PATH=$PATH" ./deployTokenA.sh
//sudo env "PATH=$PATH" ./script/bash/deployHookDeployer.sh