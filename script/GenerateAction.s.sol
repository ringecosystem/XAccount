// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@msgport/interfaces/IMessagePort.sol";
import "../src/XAccountUIFactory.sol";

/// @dev ISafeMsgportModule serves as a module integrated within the Safe system, specifically devised to enable remote administration and control of the xAccount.
interface ISafeMsgportModule {
    /// @dev Receive xCall from root chain xOwner.
    /// @param target Target of the transaction that should be executed
    /// @param value Wei value of the transaction that should be executed
    /// @param data Data of the transaction that should be executed
    /// @param operation Operation (Call or Delegatecall) of the transaction that should be executed
    /// @return xExecute return data Return data after xCall.
    function xExecute(address target, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        returns (bytes memory);

    /// Get port address;
    function port() external returns (address);
}

/// forge script script/GenerateAction.s.sol
contract GenerateActionScipt is Script {
    XAccountUIFactory UIFACTORY = XAccountUIFactory(0x1e0DBFEBD134378aaBc70a29003a9BD25B9e9E41);

    uint256 ARBITRUM_SEPOLIA_CHAINID = 421614;

    modifier broadcast() {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

    // GenerateAction on target chain(sepolia) for timelock on source chain(arbitrum-sepolia).
    function run() public {
        address source_chain_address = msg.sender;
        vm.createSelectFork("sepolia");
        // get all deployed XAccounts for xOwner(source chainid + source chaind address)
        (address[] memory xAccounts, address[] memory modules) =
            UIFACTORY.getDeployed(ARBITRUM_SEPOLIA_CHAINID, source_chain_address);
        // select one XAccount to generate action
        address xAccount = xAccounts[0];
        address module = modules[0];
        // generate call from Dapp
        address from = xAccount;
        address target = address(1);
        bytes memory data = bytes(0);
        uint256 value = 1;

        uint8 callType = 0; // Call

        // encode message
        bytes memory message =
            abi.encodeWithSelector(ISafeMsgportModule.xExecute.selector, target, value, data, callType);

        // get port
        address port = ISafeMsgportModule(module).port();

        // send msg from source chain (in tally UI)
        IMessagePort(port).send{value: fee}(ARBITRUM_SEPOLIA_CHAINID, module, message, params);
    }
}
