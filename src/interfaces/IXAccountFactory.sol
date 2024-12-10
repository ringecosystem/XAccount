// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IXAccountFactory {
    function create(bytes32 salt, uint256 fromChainId, address owner, address port, address recovery)
        external
        returns (address, address);

    function xAccountOf(address deployer, bytes32 salt, uint256 fromChainId, address owner)
        external
        view
        returns (address, address);
}
