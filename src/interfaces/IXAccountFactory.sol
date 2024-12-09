// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IXAccountFactory {
    function create(bytes32 salt, uint256 fromChainId, address owner, address port, address recovery)
        external
        returns (address, address);
}
