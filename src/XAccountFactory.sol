// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/ISafeMsgportModule.sol";
import "./interfaces/ISafeProxyFactory.sol";
import "./interfaces/ISafe.sol";
import "./utils/CREATE3.sol";

/// @title XAccountFactory
/// @dev XAccountFactory is a factory contract for create xAccount.
///   - 1 account can deploy multi xAccount on target chain for each factory.
contract XAccountFactory {
    address public immutable SAFE_MSGPORT_MODULE;
    /// Safe Deployment: https://github.com/safe-global/safe-deployments/tree/main/src/assets/v1.3.0
    address public constant safeFallbackHandler = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;
    address public constant safeSingletonL2 = 0x3E5c63644E683549055b9Be8653de26E0B4CD36E;
    ISafeProxyFactory public constant safeFactory = ISafeProxyFactory(0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2);

    address internal constant DEAD_OWNER = 0xDDdDddDdDdddDDddDDddDDDDdDdDDdDDdDDDDDDd;

    event XAccountCreated(
        address deployer,
        bytes32 salt,
        uint256 fromChainId,
        address owner,
        address xAccount,
        address module,
        address port,
        address recovery
    );

    constructor(address safeMsgportModule) {
        SAFE_MSGPORT_MODULE = safeMsgportModule;
    }

    /// @dev Create xAccount on target chain.
    /// @param salt Pseudo random number.
    /// @param fromChainId Source chain id.
    /// @param owner Owner on source chain.
    /// @param port Msgport address for send msgport.
    /// @param recovery The default safe recovery module address for xAccount.
    /// @return Deployed xAccount address.
    function create(bytes32 salt, uint256 fromChainId, address owner, address port, address recovery)
        external
        returns (address, address)
    {
        return _deploy(salt, fromChainId, owner, port, recovery);
    }

    function _deploy(bytes32 salt, uint256 fromChainId, address owner, address port, address recovery)
        internal
        returns (address proxy, address module)
    {
        address deployer = msg.sender;
        salt = keccak256(abi.encodePacked(deployer, salt, fromChainId, owner));
        (proxy, module) = _deployXAccount(salt);
        _setupProxy(proxy, module, recovery);
        _setupModule(module, proxy, fromChainId, owner, port);

        emit XAccountCreated(deployer, salt, fromChainId, owner, proxy, module, port, recovery);
    }

    function setupModules(address module, address recovery) external {
        ISafe safe = ISafe(address(this));
        safe.enableModule(module);
        if (recovery != address(0)) safe.enableModule(recovery);
    }

    function _setupProxy(address proxy, address module, address recovery) internal {
        bytes memory setupModulesData = abi.encodeWithSelector(XAccountFactory.setupModules.selector, module, recovery);
        uint256 threshold = 1;
        address[] memory owners = new address[](1);
        owners[0] = DEAD_OWNER;
        ISafe(proxy).setup(
            owners,
            threshold,
            address(this),
            setupModulesData,
            safeFallbackHandler,
            address(0x0),
            0,
            payable(address(0x0))
        );
    }

    function _setupModule(address module, address proxy, uint256 chainId, address owner, address port) internal {
        ISafeMsgportModule(module).setup(proxy, chainId, owner, port);
    }

    function _deployXAccount(bytes32 salt) internal returns (address proxy, address module) {
        (proxy, module) = CREATE3.getDeployed(salt, address(this));
        bytes memory creationCode1 = safeFactory.proxyCreationCode();
        bytes memory deploymentCode1 = abi.encodePacked(creationCode1, uint256(uint160(safeSingletonL2)));

        (proxy, module) = CREATE3.deploy(salt, deploymentCode1, SAFE_MSGPORT_MODULE);
    }

    /// @dev Calculate xAccount address.
    /// @notice The module address is only effective during its creation and may be replaced by the xAccount in the future.
    /// @param deployer who deployed the xAccount.
    /// @param salt Pseudo random number of deplyed xAccount.
    /// @param fromChainId Chain id that xAccount belongs in.
    /// @param owner Owner that xAccount belongs to.
    /// @return (xAccount address, module address).
    function xAccountOf(address deployer, bytes32 salt, uint256 fromChainId, address owner)
        public
        view
        returns (address, address)
    {
        salt = keccak256(abi.encodePacked(deployer, salt, fromChainId, owner));
        return CREATE3.getDeployed(salt, address(this));
    }
}
