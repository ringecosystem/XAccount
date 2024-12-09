// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../interfaces/ISafeMsgportModule.sol";
import "../interfaces/ISafeProxyFactory.sol";
import "../interfaces/ISafe.sol";
import "../interfaces/IPortRegistry.sol";
import "../interfaces/IMessagePort.sol";
import "../ports/base/PortMetadata.sol";
import "../user/Application.sol";
import "../utils/CREATE3.sol";

/// @title XAccountFactory
/// @dev XAccountFactory is a factory contract for create xAccount.
///   - 1 account only have 1 xAccount on target chain for each factory.
contract XAccountFactory is Ownable2Step, Application, PortMetadata {
    address public safeMsgportModule;
    address public safeFallbackHandler;
    address public safeSingleton;
    ISafeProxyFactory public safeFactory;

    IPortRegistry public immutable REGISTRY;

    address internal constant DEAD_OWNER = 0xDDdDddDdDdddDDddDDddDDDDdDdDDdDDdDDDDDDd;

    event XAccountCreated(uint256 fromChainId, address deployer, address xAccount, address module, address port);

    constructor(
        address dao,
        address module,
        address sfactory,
        address singleton,
        address fallbackHandler,
        address registry,
        string memory name
    ) PortMetadata(name) {
        _transferOwnership(dao);
        safeMsgportModule = module;
        safeSingleton = singleton;
        safeFallbackHandler = fallbackHandler;
        safeFactory = ISafeProxyFactory(sfactory);
        REGISTRY = IPortRegistry(registry);
    }

    function LOCAL_CHAINID() public view returns (uint256) {
        return block.chainid;
    }

    function setSafeFactory(address factory) external onlyOwner {
        safeFactory = ISafeProxyFactory(factory);
    }

    function setSafeSingleton(address singleton) external onlyOwner {
        safeSingleton = singleton;
    }

    function setSafeFallbackHandler(address fallbackHandler) external onlyOwner {
        safeFallbackHandler = fallbackHandler;
    }

    function setSafeMsgportModule(address module) external onlyOwner {
        safeMsgportModule = module;
    }

    function setURI(string calldata uri) external onlyOwner {
        _setURI(uri);
    }

    function isRegistred(address port) public view returns (bool) {
        return bytes(REGISTRY.get(LOCAL_CHAINID(), port)).length > 0;
    }

    function _toFactory(uint256 toChainId) internal view returns (address l) {
        l = REGISTRY.get(toChainId, name());
        require(l != address(0), "!to");
    }

    function _fromFactory(uint256 fromChainId) internal view returns (address) {
        return REGISTRY.get(fromChainId, name());
    }

    /// @dev Cross chian function for create xAccount on target chain.
    /// @notice If recovery address is `address(0)`, do not enabale recovery module.
    /// @param name Port name that used for create xAccount.
    /// @param toChainId Target chain id.
    /// @param params Port params correspond with the port.
    /// @param recovery The default safe recovery module address on target chain for xAccount.
    function xCreate(string calldata name, uint256 toChainId, bytes calldata params, address recovery)
        external
        payable
    {
        uint256 fee = msg.value;
        require(toChainId != LOCAL_CHAINID(), "!toChainId");

        address deployer = msg.sender;
        bytes memory encoded = abi.encodeWithSelector(XAccountFactory.xDeploy.selector, deployer, recovery);
        address port = REGISTRY.get(LOCAL_CHAINID(), name);
        IMessagePort(port).send{value: fee}(toChainId, _toFactory(toChainId), encoded, params);
    }

    /// @dev Create xAccount on target chain.
    /// @notice Only could be called by source chain.
    /// @param deployer Deployer on source chain.
    /// @param recovery The default safe recovery module address for xAccount.
    /// @return Deployed xAccount address.
    function xDeploy(address deployer, address recovery) external returns (address, address) {
        address port = _msgPort();
        uint256 fromChainId = _fromChainId();
        require(isRegistred(port), "!port");
        require(_xmsgSender() == _fromFactory(fromChainId), "!xmsgSender");

        return _deploy(fromChainId, deployer, port, recovery);
    }

    function _deploy(uint256 chainId, address deployer, address port, address recovery)
        internal
        returns (address proxy, address module)
    {
        require(chainId != LOCAL_CHAINID(), "!chainId");

        bytes32 salt = keccak256(abi.encodePacked(chainId, deployer));
        (proxy, module) = _deployXAccount(salt);
        _setupProxy(proxy, module, recovery);
        _setupModule(module, proxy, chainId, deployer, port);

        emit XAccountCreated(chainId, deployer, proxy, module, port);
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

    function _setupModule(address module, address proxy, uint256 chainId, address deployer, address port) internal {
        ISafeMsgportModule(module).setup(proxy, chainId, deployer, port);
    }

    function _deployXAccount(bytes32 salt) internal returns (address proxy, address module) {
        (proxy, module) = CREATE3.getDeployed(salt, address(this));
        bytes memory creationCode1 = safeFactory.proxyCreationCode();
        bytes memory deploymentCode1 = abi.encodePacked(creationCode1, uint256(uint160(safeSingleton)));

        (proxy, module) = CREATE3.deploy(salt, deploymentCode1, safeMsgportModule);
    }

    /// @dev Calculate xAccount address on target chain.
    /// @notice The module address is only effective during its creation and may be replaced by the xAccount in the future.
    /// @param fromChainId Chain id that xAccount belongs in.
    /// @param toChainId Chain id that xAccount lives in.
    /// @param deployer Owner that xAccount belongs to.
    /// @return (xAccount address, module address).
    function xAccountOf(uint256 fromChainId, uint256 toChainId, address deployer)
        public
        view
        returns (address, address)
    {
        return xAccountOf(fromChainId, deployer, _toFactory(toChainId));
    }

    /// @dev Calculate xAccount address.
    /// @notice The module address is only effective during its creation and may be replaced by the xAccount in the future.
    /// @param fromChainId Chain id that xAccount belongs in.
    /// @param deployer Owner that xAccount belongs to.
    /// @param factory Factory that create xAccount.
    /// @return (xAccount address, module address).
    function xAccountOf(uint256 fromChainId, address deployer, address factory)
        public
        pure
        returns (address, address)
    {
        bytes32 salt = keccak256(abi.encodePacked(fromChainId, deployer));
        return CREATE3.getDeployed(salt, factory);
    }
}
