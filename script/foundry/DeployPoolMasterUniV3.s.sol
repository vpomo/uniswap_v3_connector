// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PoolMasterUniV3} from "../../src/PoolMasterUniV3.sol";

/**
 * @title DeployPoolMasterUniV3
 * @notice Скрипт для деплоя контракта DeployPoolMasterUniV3 с использованием Foundry.
 * @dev Скрипт читает конфигурацию
 */
contract DeployPoolMasterUniV3 is Script {
    function run() external returns (address proxyAddress) {
        // https://docs.uniswap.org/contracts/v3/reference/deployments
        address positionManager = 0x6b2937Bde17889EDCf8fbD8dE31C3C2a70Bc4d65;
        address router = 0x4A7b5Da61326A6379179b40d00F57E5bbDC962c2;
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

        // --- 1. Загрузка конфигурации ---
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(deployerPrivateKey != 0, "PRIVATE_KEY must be set in .env file");

        address owner = vm.envAddress("OWNER_ADDRESS");
        if (owner == address(0)) {
            owner = vm.addr(deployerPrivateKey);
        }

        console.log("Starting deployment PoolMasterUniV3 ...");
        console.log("  - Deployer: %s", vm.toString(vm.addr(deployerPrivateKey)));
        console.log("  - Designated Owner: %s", vm.toString(owner));

        // --- 2. Деплой ---
        vm.startBroadcast(deployerPrivateKey);

        // a. Деплой контракта с логикой (implementation)
        PoolMasterUniV3 logicContract = new PoolMasterUniV3();
        console.log("  - Logic contract deployed to: %s", address(logicContract));

        // b. Подготовка данных для инициализации прокси
        // Мы вызовем функцию `initialize(address initialOwner)`
        bytes memory initData = abi.encodeCall(PoolMasterUniV3.initialize, (owner, positionManager, router, permit2));

        // c. Деплой прокси-контракта, который указывает на логику и инициализируется
        ERC1967Proxy proxy = new ERC1967Proxy(address(logicContract), initData);
        proxyAddress = address(proxy);

        vm.stopBroadcast();

        console.log("Deployment successful!");
        console.log("   - Proxy contract address: %s", proxyAddress);

        return proxyAddress;
    }

    /**
     * @dev Вспомогательная функция для преобразования адреса в checksum-формат для красивого вывода.
     */
    function toChecksum(address addr) private pure returns (string memory) {
        return vm.toString(addr);
    }
}

//sudo env "PATH=$PATH" ./script/bash/deployPoolMasterUniV3.sh