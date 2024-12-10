// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IXAccountFactory.sol";

contract XAccountUIFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    IXAccountFactory public immutable FACTORY;

    // fromChainId => owner => xAccounts
    mapping(uint256 => mapping(address => EnumerableSet.AddressSet)) private _xAccounts;
    // fromChainId => owner => module
    mapping(uint256 => mapping(address => EnumerableSet.AddressSet)) private _modules;
    // fromChainId => owner => xAccounts => deployer
    mapping(uint256 => mapping(address => mapping(address => address))) public deployers;

    constructor(address factory) {
        FACTORY = IXAccountFactory(factory);
    }

    /// Create xAccount using deployer(msg.sender) as salt.
    function create(uint256 fromChainId, address owner, address port, address recovery)
        external
        returns (address xAccount, address module)
    {
        address deployer = msg.sender;
        bytes32 salt = keccak256(abi.encodePacked(deployer));
        (xAccount, module) = FACTORY.create(salt, fromChainId, owner, port, recovery);
        require(_xAccounts[fromChainId][owner].add(xAccount), "!addXAccunt");
        require(_modules[fromChainId][owner].add(module), "!addModule");
        deployers[fromChainId][owner][xAccount] = deployer;
    }

    /// Get all deployed xAccount by xOwner(fromChainId, owner).
    function getDeployed(uint256 fromChainId, address owner) public view returns (address[] memory) {
        return _xAccounts[fromChainId][owner].values();
    }

    /// Caculate xAccount address.
    function xAccountOf(address deployer, uint256 fromChainId, address owner) public view returns (address, address) {
        bytes32 salt = keccak256(abi.encodePacked(deployer));
        return FACTORY.xAccountOf(address(this), salt, fromChainId, owner);
    }
}
