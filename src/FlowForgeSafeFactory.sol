// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeProxyFactory} from "../lib/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "../lib/safe-contracts/contracts/proxies/SafeProxy.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title FlowForgeSafeFactory
 * @notice Factory contract for creating Safe wallets for FlowForge users.
 * @dev Owner can create Safes and setExecutor. Executor (relayer) can create Safes for users.
 *      When deployed via CREATE3, pass _initialOwner so the deployer EOA is owner, not the CREATE3 proxy.
 */
contract FlowForgeSafeFactory is Ownable {
    // Maps a user to their Safe wallets.
    mapping(address => address[]) private userSafeWallets;
    // Maps a user to their current saltNonce for deterministic address generation.
    mapping(address => uint256) private userSaltNonces;

    address public immutable SAFE_PROXY_FACTORY;
    address public immutable SAFE_SINGLETON;

    /// @notice keccak256 of the on-chain SafeProxyFactory's actual deployment code
    ///         (proxyCreationCode ++ uint256(singleton)). Fetched at construction so
    ///         predictSafeAddress matches the real CREATE2 even when our local
    ///         SafeProxy compilation differs from the canonical on-chain bytecode.
    bytes32 public immutable PROXY_DEPLOY_CODE_HASH;

    /// @notice Address allowed to call createSafeWallet (e.g. backend relayer). Updatable by owner.
    address public executor;

    event SafeWalletCreated(address indexed user, address indexed safeWallet, uint256 saltNonce);
    event ExecutorSet(address indexed previousExecutor, address indexed newExecutor);

    error NotOwnerOrExecutor();

    modifier onlyOwnerOrExecutor() {
        if (msg.sender != owner() && msg.sender != executor) revert NotOwnerOrExecutor();
        _;
    }

    /// @param _initialOwner Owner (e.g. deployer). Use address(0) to use msg.sender.
    /// @param _executor Address that may call createSafeWallet (e.g. backend relayer).
    constructor(address _safeProxyFactory, address _safeSingleton, address _initialOwner, address _executor)
        Ownable(_initialOwner != address(0) ? _initialOwner : msg.sender)
    {
        require(_safeProxyFactory != address(0), "Zero proxy factory");
        require(_safeSingleton != address(0), "Zero singleton");
        require(_executor != address(0), "Zero executor");
        SAFE_PROXY_FACTORY = _safeProxyFactory;
        SAFE_SINGLETON = _safeSingleton;
        executor = _executor;

        bytes memory onChainCreationCode = SafeProxyFactory(_safeProxyFactory).proxyCreationCode();
        PROXY_DEPLOY_CODE_HASH = keccak256(
            abi.encodePacked(onChainCreationCode, uint256(uint160(_safeSingleton)))
        );
    }

    /// @notice Set the executor (relayer). Only the owner can call this.
    function setExecutor(address _executor) external onlyOwner {
        require(_executor != address(0), "Zero executor");
        address previous = executor;
        executor = _executor;
        emit ExecutorSet(previous, _executor);
    }

    /**
     * @notice Deploy a new Safe wallet for a user with the user as the sole owner.
     * @dev This function follows the same deployment pattern as the Safe Core SDK:
     *      1. Encodes the setup call with user as sole owner and threshold of 1
     *      2. Uses SafeProxyFactory.createProxyWithNonce with an incrementing saltNonce
     *      3. The saltNonce ensures deterministic addresses and prevents collisions
     * @param user The user who will own this Safe wallet.
     * @return safeAddress The address of the deployed Safe wallet.
     */
    function createSafeWallet(address user) external onlyOwnerOrExecutor returns (address safeAddress) {
        require(user != address(0), "Zero user");

        uint256 saltNonce = userSaltNonces[user];
        userSaltNonces[user] = saltNonce + 1;

        address[] memory owners = new address[](1);
        owners[0] = user;

        bytes memory initializer = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners, 1, address(0), "", address(0), address(0), 0, address(0)
        );

        // Predict the real on-chain CREATE2 address using the canonical creation
        // code hash (may differ from our locally-compiled SafeProxy bytecode).
        address predicted = _predictWithOnChainCode(initializer, saltNonce);

        // If a proxy already exists (e.g. from a previous factory deployment that
        // used the same SafeProxyFactory + singleton + saltNonce), adopt it instead
        // of calling createProxyWithNonce which would revert with "Create2 call failed".
        if (predicted.code.length > 0) {
            userSafeWallets[user].push(predicted);
            emit SafeWalletCreated(user, predicted, saltNonce);
            return predicted;
        }

        SafeProxyFactory factory = SafeProxyFactory(SAFE_PROXY_FACTORY);
        SafeProxy safeProxy = factory.createProxyWithNonce(SAFE_SINGLETON, initializer, saltNonce);

        safeAddress = address(safeProxy);
        require(safeAddress != address(0), "Zero proxy");
        userSafeWallets[user].push(safeAddress);
        emit SafeWalletCreated(user, safeAddress, saltNonce);
        return safeAddress;
    }

    /**
     * @notice Returns all Safe wallets created for a particular user.
     * @param user The owner's address.
     * @return Array of Safe wallet addresses.
     */
    function getSafeWallets(address user) external view returns (address[] memory) {
        return userSafeWallets[user];
    }

    /**
     * @notice Returns the most recently created Safe wallet for a user, or address(0) if none.
     * @param user The owner's address.
     * @return The address of the most recent Safe wallet, or address(0) if none exists.
     */
    function latestSafeWallet(address user) external view returns (address) {
        address[] storage wallets = userSafeWallets[user];
        if (wallets.length == 0) return address(0);
        return wallets[wallets.length - 1];
    }

    /**
     * @notice Returns the current saltNonce for a user.
     * @dev This can be used to predict the address of the next Safe wallet for a user.
     * @param user The owner's address.
     * @return The current saltNonce value.
     */
    function getUserSaltNonce(address user) external view returns (uint256) {
        return userSaltNonces[user];
    }

    /**
     * @notice Calculates the predicted address for a user's next Safe wallet.
     * @dev Uses PROXY_DEPLOY_CODE_HASH (fetched from the canonical on-chain
     *      SafeProxyFactory at deploy time) so the prediction matches the real
     *      CREATE2 address regardless of local Solidity compiler version.
     * @param user The user who will own the Safe wallet.
     * @return predictedAddress The predicted address of the next Safe wallet.
     */
    function predictSafeAddress(address user) external view returns (address predictedAddress) {
        require(user != address(0), "Zero user");

        uint256 saltNonce = userSaltNonces[user];

        address[] memory owners = new address[](1);
        owners[0] = user;

        bytes memory initializer = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners, 1, address(0), "", address(0), address(0), 0, address(0)
        );

        predictedAddress = _predictWithOnChainCode(initializer, saltNonce);
    }

    /// @dev Compute the real CREATE2 address the canonical SafeProxyFactory will use.
    function _predictWithOnChainCode(bytes memory initializer, uint256 saltNonce) internal view returns (address predicted) {
        bytes32 salt;
        assembly {
            let inner := keccak256(add(initializer, 32), mload(initializer))
            mstore(0x80, inner)
            mstore(0xa0, saltNonce)
            salt := keccak256(0x80, 64)
        }

        address factory_ = SAFE_PROXY_FACTORY;
        bytes32 codeHash = PROXY_DEPLOY_CODE_HASH;
        bytes32 hash;
        assembly {
            mstore(0x80, or(shl(248, 0xff), shl(96, factory_)))
            mstore(0xa0, salt)
            mstore(0xc0, codeHash)
            hash := keccak256(0x80, 85)
        }

        predicted = address(uint160(uint256(hash)));
    }
}
