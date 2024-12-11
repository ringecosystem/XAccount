// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/XAccountUIFactory.sol";

/// forge script script/CreateXAccount.s.sol
contract CreateXAccountScript is Script {
    XAccountUIFactory UIFACTORY = XAccountUIFactory(0x1e0DBFEBD134378aaBc70a29003a9BD25B9e9E41);
    address ORMPUPGRADEABLEPORT = 0x2cd1867Fb8016f93710B6386f7f9F1D540A60812;

    uint256 ARBITRUM_SEPOLIA_CHAINID = 421614;

    modifier broadcast() {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

    // Create XAccount on target chain(sepolia) for timelock on source chain(arbitrum-sepolia).
    function run() public {
        address mockedTimelockContract = msg.sender;
        vm.createSelectFork("sepolia");
        createXAccount(ARBITRUM_SEPOLIA_CHAINID, mockedTimelockContract, ORMPUPGRADEABLEPORT, address(0));
    }

    /// @dev The function is utilized to create a xAccount on the target chain.
    /// @param fromChainId Source chain id.
    /// @param timelock Timelock contract address on source chain.
    /// @param port Msgport address for send msgport.
    /// @param recovery The default safe recovery module address for xAccount.
    function createXAccount(uint256 fromChainId, address timelock, address port, address recovery) public broadcast {
        UIFACTORY.create(fromChainId, timelock, port, recovery);
    }
}
