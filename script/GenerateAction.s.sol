// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Surl} from "surl/Surl.sol";
import "forge-std/Script.sol";
import "@msgport/interfaces/IMessagePort.sol";
import "../src/XAccountUIFactory.sol";

interface IMessagePortPeerLookup {
    function peerOf(uint256 chainId) external view returns (address);
}

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

/// forge script script/GenerateAction.s.sol --ffi --via-ir
contract GenerateActionScript is Script {
    using Surl for *;
    using stdJson for string;

    XAccountUIFactory UIFACTORY = XAccountUIFactory(0x1e0DBFEBD134378aaBc70a29003a9BD25B9e9E41);

    uint256 ARBITRUM_SEPOLIA_CHAINID = 421614;
    uint256 SEPOLIA_CHAINID = 11155111;

    // GenerateAction on target chain(sepolia) for timelock on source chain(arbitrum-sepolia).
    function run() public {
        address mockedTimelockContract = msg.sender;
        vm.createSelectFork("sepolia");
        // get all deployed XAccounts for xOwner(source chainid + source TimelockContract address)
        (address[] memory xAccounts, address[] memory modules) =
            UIFACTORY.getDeployed(ARBITRUM_SEPOLIA_CHAINID, mockedTimelockContract);
        // select one XAccount to generate action
        address xAccount = xAccounts[0];
        address module = modules[0];
        // generate call from Dapp
        address from = xAccount;
        address target = address(1);
        bytes memory data = new bytes(0);
        uint256 value = 1;

        uint8 callType = 0; // Call

        // encode message
        bytes memory message =
            abi.encodeWithSelector(ISafeMsgportModule.xExecute.selector, target, value, data, callType);

        // get port
        address targetPort = ISafeMsgportModule(module).port();
        address sourcePort = IMessagePortPeerLookup(targetPort).peerOf(ARBITRUM_SEPOLIA_CHAINID);

        // post request to msgport api
        // see more on `https://github.com/ringecosystem/msgport-api?tab=readme-ov-file`
        string[] memory headers = new string[](1);
        headers[0] = "Content-Type: application/json";
        (, bytes memory response) = "https://api.msgport.xyz/v2/fee_with_options".post(
            headers,
            '{"fromChainId": 421614, "fromAddress": "0x0f14341A7f464320319025540E8Fe48Ad0fe5aec", "toChainId": 11155111, "toAddress": "0xB8a2fF70DFA171ffbfE869Cfc88A25f310cb837f", "message": "0x5fa9b40300000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", "ormp": { "refundAddress": "0x0f14341A7f464320319025540E8Fe48Ad0fe5aec" } }'
        );

        string memory rs = string(response);
        bytes memory params = rs.readBytes(".data.params");
        uint256 fee = rs.readUint(".data.fee");

        {
            /// Here we go.
            /// Target: sourcePort
            /// Function: IMessagePort.send.selector
            /// Function Params:
            ///    - toChainId: ARBITRUM_SEPOLIA_CHAINID
            ///    - toDapp: module
            ///    - message: message
            ///    - params params
            /// Value: fee
            // send msg from source chain (in tally UI)
            vm.createSelectFork("arbitrum-sepolia");
            vm.startBroadcast();
            IMessagePort(sourcePort).send{value: fee}(SEPOLIA_CHAINID, module, message, params);
            vm.stopBroadcast();
        }
    }
}
