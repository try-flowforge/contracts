// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {INameWrapper} from "./interfaces/INameWrapper.sol";
import {IFlowForgeSubdomainPricer} from "./interfaces/IFlowForgeSubdomainPricer.sol";
import {IFlowForgeSubdomainPricerMultiToken} from "./interfaces/IFlowForgeSubdomainPricerMultiToken.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {ERC1155Holder} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

// Fuse bits from ENS Name Wrapper (must match deployed wrapper)
uint32 constant PARENT_CANNOT_CONTROL = 1 << 16;
uint32 constant IS_DOT_ETH = 1 << 17;

error Unavailable();
error Unauthorised(bytes32 node);
error NameNotRegistered();
error NameNotSetup(bytes32 node);
error DataMissing();
error ParentExpired(bytes32 node);
error ParentNotWrapped(bytes32 node);
error DurationTooLong(bytes32 node);
error ParentNameNotSetup(bytes32 parentNode);
error InsufficientPayment();
error InsufficientBalance();
error PricerNotUSDC();

struct DomainConfig {
    IFlowForgeSubdomainPricer pricer;
    address beneficiary;
    bool active;
}

/**
 * @title FlowForgeSubdomainRegistry
 * @notice Rental subdomain registrar for a single ENS parent (e.g. flowforge.eth). Users pay to register
 *         or renew subdomains (ETH or ERC-20 via pricer); expiry gates gas sponsorship off-chain.
 *         Supports treasury mode: users deposit ETH/USDC and registerFromBalance/renewFromBalance
 *         use the contract's balance so the registration tx only costs gas.
 * @dev Parent must be wrapped in the ENS Name Wrapper. Owner of parent must call setupDomain and
 *      NameWrapper.setApprovalForAll(registry, true). User deposits are non-refundable; there is
 *      no withdraw or cancel for users. Only the registry owner may withdraw from the treasury.
 */
contract FlowForgeSubdomainRegistry is ERC1155Holder, Ownable {
    using Address for address;

    uint64 internal constant GRACE_PERIOD = 90 days;

    INameWrapper public immutable WRAPPER;
    IERC20 public immutable USDC;
    IAggregatorV3 public immutable ETH_USD_FEED;
    mapping(bytes32 => DomainConfig) public names;
    /// @notice User balance in USDC (6 decimals). Used by registerFromBalance / renewFromBalance.
    mapping(address => uint256) public balanceOf;

    event NameRegistered(bytes32 indexed node, uint64 expiry);
    event NameRenewed(bytes32 indexed node, uint64 expiry);
    event NameSetup(bytes32 indexed node, address pricer, address beneficiary, bool active);
    event Deposit(address indexed user, address token, uint256 amount, uint256 balanceCredits);
    event Withdrawal(address indexed to, address token, uint256 amount);

    constructor(address _wrapper, address _usdc, address _ethUsdFeed) Ownable(msg.sender) {
        require(_wrapper != address(0), "Zero wrapper");
        require(_usdc != address(0), "Zero USDC");
        require(_ethUsdFeed != address(0), "Zero feed");
        WRAPPER = INameWrapper(_wrapper);
        USDC = IERC20(_usdc);
        ETH_USD_FEED = IAggregatorV3(_ethUsdFeed);
    }

    modifier authorised(bytes32 node) {
        _authorised(node);
        _;
    }

    function _authorised(bytes32 node) internal view {
        if (!WRAPPER.canModifyName(node, msg.sender)) revert Unauthorised(node);
    }

    /**
     * @notice Configure a parent domain for subdomain registration. Caller must be able to modify the name (owner).
     * @param node Namehash of the parent (e.g. namehash("flowforge.eth")).
     * @param pricer Pricer contract; return (address(0), amount) for ETH or (token, amount) for ERC-20.
     * @param beneficiary Receives registration/renewal fees.
     * @param active If false, register/renew will revert with ParentNameNotSetup.
     */
    function setupDomain(
        bytes32 node,
        IFlowForgeSubdomainPricer pricer,
        address beneficiary,
        bool active
    ) external authorised(node) {
        names[node] = DomainConfig({pricer: pricer, beneficiary: beneficiary, active: active});
        emit NameSetup(node, address(pricer), beneficiary, active);
    }

    /**
     * @notice Register a subdomain. User pays via ETH (if pricer returns token==0) or ERC-20 (approve first).
     * @param parentNode Namehash of the parent.
     * @param label Subdomain label (e.g. "alice" for alice.flowforge.eth).
     * @param newOwner Owner of the new subname (typically the user's EOA).
     * @param resolver Resolver for the subname; use address(0) for default or set text records via records.
     * @param duration Registration duration in seconds (e.g. 365 days).
     * @param records Optional: encoded resolver calldata (e.g. setText). First 32 bytes of each must be the subname's namehash.
     */
    function register(
        bytes32 parentNode,
        string calldata label,
        address newOwner,
        address resolver,
        uint64 duration,
        bytes[] calldata records
    ) external payable {
        if (!names[parentNode].active) revert ParentNameNotSetup(parentNode);

        (address token, uint256 fee) = names[parentNode].pricer.price(parentNode, label, duration);
        _checkParent(parentNode, duration);

        if (token == address(0)) {
            if (msg.value < fee) revert InsufficientPayment();
            if (fee > 0) {
                (bool ok,) = payable(names[parentNode].beneficiary).call{value: fee}("");
                require(ok, "ETH transfer failed");
            }
            if (msg.value > fee) {
                (bool refund,) = payable(msg.sender).call{value: msg.value - fee}("");
                require(refund, "Refund failed");
            }
        } else {
            if (msg.value != 0) revert InsufficientPayment();
            if (fee > 0) {
                require(IERC20(token).transferFrom(msg.sender, names[parentNode].beneficiary, fee), "ERC20 transfer failed");
            }
        }

        uint64 expiry = uint64(block.timestamp) + duration;
        _register(parentNode, label, newOwner, resolver, expiry, records);
    }

    /**
     * @notice Register a subdomain paying in a specific token (ETH or ERC-20). Pricer must implement priceForToken.
     * @param paymentToken address(0) to pay in ETH; otherwise the ERC-20 token address (e.g. USDC).
     */
    function registerWithToken(
        bytes32 parentNode,
        string calldata label,
        address newOwner,
        address resolver,
        uint64 duration,
        bytes[] calldata records,
        address paymentToken
    ) external payable {
        if (!names[parentNode].active) revert ParentNameNotSetup(parentNode);
        uint256 fee = IFlowForgeSubdomainPricerMultiToken(address(names[parentNode].pricer)).priceForToken(
            parentNode, label, duration, paymentToken
        );
        _checkParent(parentNode, duration);
        _collectPayment(parentNode, paymentToken, fee);
        uint64 expiry = uint64(block.timestamp) + duration;
        _register(parentNode, label, newOwner, resolver, expiry, records);
    }

    /**
     * @notice Renew an existing subdomain. Payment same as register (ETH or ERC-20 per pricer).
     */
    function renew(bytes32 parentNode, string calldata label, uint64 duration)
        external
        payable
        returns (uint64 newExpiry)
    {
        _checkParent(parentNode, duration);

        (address token, uint256 fee) = names[parentNode].pricer.price(parentNode, label, duration);
        if (token == address(0)) {
            if (msg.value < fee) revert InsufficientPayment();
            if (fee > 0) {
                (bool ok,) = payable(names[parentNode].beneficiary).call{value: fee}("");
                require(ok, "ETH transfer failed");
            }
            if (msg.value > fee) {
                (bool refund,) = payable(msg.sender).call{value: msg.value - fee}("");
                require(refund, "Refund failed");
            }
        } else {
            if (msg.value != 0) revert InsufficientPayment();
            if (fee > 0) {
                require(IERC20(token).transferFrom(msg.sender, names[parentNode].beneficiary, fee), "ERC20 transfer failed");
            }
        }

        return _renew(parentNode, label, duration);
    }

    /**
     * @notice Renew paying in a specific token. Pricer must implement priceForToken.
     */
    function renewWithToken(
        bytes32 parentNode,
        string calldata label,
        uint64 duration,
        address paymentToken
    ) external payable returns (uint64 newExpiry) {
        _checkParent(parentNode, duration);
        uint256 fee = IFlowForgeSubdomainPricerMultiToken(address(names[parentNode].pricer)).priceForToken(
            parentNode, label, duration, paymentToken
        );
        _collectPayment(parentNode, paymentToken, fee);
        return _renew(parentNode, label, duration);
    }

    /**
     * @notice Batch register subdomains. Pays total fee in one go (ETH or ERC-20 depending on pricer).
     */
    function batchRegister(
        bytes32 parentNode,
        string[] calldata labels,
        address[] calldata newOwners,
        address resolver,
        uint64 duration,
        bytes[][] calldata records
    ) external payable {
        if (labels.length != newOwners.length || labels.length != records.length) revert DataMissing();
        DomainConfig memory cfg = names[parentNode];
        if (!cfg.active) revert ParentNameNotSetup(parentNode);
        _checkParent(parentNode, duration);

        uint256 totalEth;
        for (uint256 i = 0; i < labels.length; i++) {
            (address token, uint256 price) = cfg.pricer.price(parentNode, labels[i], duration);
            if (token == address(0)) {
                totalEth += price;
            } else {
                if (price > 0) {
                    require(IERC20(token).transferFrom(msg.sender, cfg.beneficiary, price), "ERC20 transfer failed");
                }
            }
        }
        if (totalEth > 0) {
            if (msg.value < totalEth) revert InsufficientPayment();
            (bool ok,) = payable(cfg.beneficiary).call{value: totalEth}("");
            require(ok, "ETH transfer failed");
            if (msg.value > totalEth) {
                (bool refund,) = payable(msg.sender).call{value: msg.value - totalEth}("");
                require(refund, "Refund failed");
            }
        } else {
            if (msg.value != 0) revert InsufficientPayment();
        }

        uint64 expiry = uint64(block.timestamp) + duration;
        for (uint256 i = 0; i < labels.length; i++) {
            _register(parentNode, labels[i], newOwners[i], resolver, expiry, records[i]);
        }
    }

    /**
     * @notice Batch register paying in a specific token. Pricer must implement priceForToken.
     */
    function batchRegisterWithToken(
        bytes32 parentNode,
        string[] calldata labels,
        address[] calldata newOwners,
        address resolver,
        uint64 duration,
        bytes[][] calldata records,
        address paymentToken
    ) external payable {
        if (labels.length != newOwners.length || labels.length != records.length) revert DataMissing();
        DomainConfig memory cfg = names[parentNode];
        if (!cfg.active) revert ParentNameNotSetup(parentNode);
        _checkParent(parentNode, duration);
        uint256 totalFee;
        for (uint256 i = 0; i < labels.length; i++) {
            totalFee += IFlowForgeSubdomainPricerMultiToken(address(cfg.pricer)).priceForToken(
                parentNode, labels[i], duration, paymentToken
            );
        }
        _collectPayment(parentNode, paymentToken, totalFee);
        uint64 expiry = uint64(block.timestamp) + duration;
        for (uint256 i = 0; i < labels.length; i++) {
            _register(parentNode, labels[i], newOwners[i], resolver, expiry, records[i]);
        }
    }

    /**
     * @notice Batch renew subdomains.
     */
    function batchRenew(bytes32 parentNode, string[] calldata labels, uint64 duration) external payable {
        if (labels.length == 0) revert DataMissing();
        DomainConfig memory cfg = names[parentNode];
        _checkParent(parentNode, duration);

        uint256 totalEth;
        for (uint256 i = 0; i < labels.length; i++) {
            (address token, uint256 price) = cfg.pricer.price(parentNode, labels[i], duration);
            if (token == address(0)) {
                totalEth += price;
            } else {
                if (price > 0) {
                    require(IERC20(token).transferFrom(msg.sender, cfg.beneficiary, price), "ERC20 transfer failed");
                }
            }
        }
        if (totalEth > 0) {
            if (msg.value < totalEth) revert InsufficientPayment();
            (bool ok,) = payable(cfg.beneficiary).call{value: totalEth}("");
            require(ok, "ETH transfer failed");
            if (msg.value > totalEth) {
                (bool refund,) = payable(msg.sender).call{value: msg.value - totalEth}("");
                require(refund, "Refund failed");
            }
        } else {
            if (msg.value != 0) revert InsufficientPayment();
        }

        for (uint256 i = 0; i < labels.length; i++) {
            _renew(parentNode, labels[i], duration);
        }
    }

    /**
     * @notice Batch renew paying in a specific token. Pricer must implement priceForToken.
     */
    function batchRenewWithToken(
        bytes32 parentNode,
        string[] calldata labels,
        uint64 duration,
        address paymentToken
    ) external payable {
        if (labels.length == 0) revert DataMissing();
        DomainConfig memory cfg = names[parentNode];
        _checkParent(parentNode, duration);
        uint256 totalFee;
        for (uint256 i = 0; i < labels.length; i++) {
            totalFee += IFlowForgeSubdomainPricerMultiToken(address(cfg.pricer)).priceForToken(
                parentNode, labels[i], duration, paymentToken
            );
        }
        _collectPayment(parentNode, paymentToken, totalFee);
        for (uint256 i = 0; i < labels.length; i++) {
            _renew(parentNode, labels[i], duration);
        }
    }

    /**
     * @notice Returns true if the subname is available (not registered or expired).
     */
    function available(bytes32 node) public view returns (bool) {
        try WRAPPER.getData(uint256(node)) returns (address, uint32, uint64 expiry) {
            return expiry < block.timestamp;
        } catch {
            return true;
        }
    }

    // -------- treasury: deposit and register/renew from balance (tx pays only gas) --------

    /**
     * @notice Deposit ETH; credits the sender's balance in USDC equivalent (Chainlink ETH/USD).
     *         Use registerFromBalance / renewFromBalance to spend the balance (tx pays only gas).
     *         Deposits are final and non-refundable; users cannot withdraw or cancel.
     */
    function depositEth() external payable {
        if (msg.value == 0) return;
        (, int256 answer,,,) = ETH_USD_FEED.latestRoundData();
        require(answer > 0, "Invalid price");
        // casting to uint256 is safe because we require answer > 0 above
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 ethUsd8 = uint256(int256(answer));
        // credits (USDC 6 decimals) = msg.value * ethUsd8 / 1e8 * 1e6 / 1e18 = msg.value * ethUsd8 / 1e20
        uint256 credits = (msg.value * ethUsd8) / 1e20;
        require(credits > 0, "Amount too small");
        balanceOf[msg.sender] += credits;
        emit Deposit(msg.sender, address(0), msg.value, credits);
    }

    /**
     * @notice Deposit USDC; credits the sender's balance 1:1 (6 decimals).
     *         Deposits are final and non-refundable; users cannot withdraw or cancel.
     */
    function depositUsdc(uint256 amount) external {
        if (amount == 0) return;
        require(USDC.transferFrom(msg.sender, address(this), amount), "USDC transfer failed");
        balanceOf[msg.sender] += amount;
        emit Deposit(msg.sender, address(USDC), amount, amount);
    }

    /**
     * @notice Register a subdomain using the sender's balance (no msg.value). Fee is paid from contract treasury.
     *         Domain's pricer must return USDC. Duration must be whole weeks (0.5 USDC per week).
     */
    function registerFromBalance(
        bytes32 parentNode,
        string calldata label,
        address newOwner,
        address resolver,
        uint64 duration,
        bytes[] calldata records
    ) external {
        if (!names[parentNode].active) revert ParentNameNotSetup(parentNode);
        (address token, uint256 fee) = names[parentNode].pricer.price(parentNode, label, duration);
        if (token != address(USDC)) revert PricerNotUSDC();
        if (balanceOf[msg.sender] < fee) revert InsufficientBalance();
        _checkParent(parentNode, duration);
        balanceOf[msg.sender] -= fee;
        _payBeneficiary(parentNode, fee);
        uint64 expiry = uint64(block.timestamp) + duration;
        _register(parentNode, label, newOwner, resolver, expiry, records);
    }

    /**
     * @notice Renew a subdomain using the sender's balance (no msg.value). Fee is paid from contract treasury.
     */
    function renewFromBalance(bytes32 parentNode, string calldata label, uint64 duration)
        external
        returns (uint64 newExpiry)
    {
        (address token, uint256 fee) = names[parentNode].pricer.price(parentNode, label, duration);
        if (token != address(USDC)) revert PricerNotUSDC();
        if (balanceOf[msg.sender] < fee) revert InsufficientBalance();
        _checkParent(parentNode, duration);
        balanceOf[msg.sender] -= fee;
        _payBeneficiary(parentNode, fee);
        return _renew(parentNode, label, duration);
    }

    /**
     * @notice Owner withdraws ETH from the registry treasury. Only the owner may withdraw;
     *         users have no withdraw or cancel—deposits are non-refundable.
     */
    function withdrawEth(uint256 amount) external onlyOwner {
        if (amount == 0) return;
        (bool ok,) = payable(owner()).call{value: amount}("");
        require(ok, "ETH transfer failed");
        emit Withdrawal(owner(), address(0), amount);
    }

    /**
     * @notice Owner withdraws USDC from the registry treasury. Only the owner may withdraw;
     *         users have no withdraw or cancel—deposits are non-refundable.
     */
    function withdrawUsdc(uint256 amount) external onlyOwner {
        if (amount == 0) return;
        require(USDC.transfer(owner(), amount), "USDC transfer failed");
        emit Withdrawal(owner(), address(USDC), amount);
    }

    // -------- internal --------

    function _collectPayment(bytes32 parentNode, address paymentToken, uint256 fee) internal {
        address beneficiary = names[parentNode].beneficiary;
        if (paymentToken == address(0)) {
            if (msg.value < fee) revert InsufficientPayment();
            if (fee > 0) {
                (bool ok,) = payable(beneficiary).call{value: fee}("");
                require(ok, "ETH transfer failed");
            }
            if (msg.value > fee) {
                (bool refund,) = payable(msg.sender).call{value: msg.value - fee}("");
                require(refund, "Refund failed");
            }
        } else {
            if (msg.value != 0) revert InsufficientPayment();
            if (fee > 0) {
                require(IERC20(paymentToken).transferFrom(msg.sender, beneficiary, fee), "ERC20 transfer failed");
            }
        }
    }

    /// @dev Pay beneficiary amountUsdc (6 decimals). Prefer USDC; if insufficient, pay equivalent in ETH via Chainlink.
    function _payBeneficiary(bytes32 parentNode, uint256 amountUsdc) internal {
        address beneficiary = names[parentNode].beneficiary;
        if (amountUsdc == 0) return;
        uint256 usdcBalance = USDC.balanceOf(address(this));
        if (usdcBalance >= amountUsdc) {
            require(USDC.transfer(beneficiary, amountUsdc), "USDC transfer failed");
            return;
        }
        (, int256 answer,,,) = ETH_USD_FEED.latestRoundData();
        require(answer > 0, "Invalid price");
        // casting to uint256 is safe because we require answer > 0 above
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 ethUsd8 = uint256(int256(answer));
        uint256 ethAmount = (amountUsdc * 1e20) / ethUsd8;
        require(address(this).balance >= ethAmount, "Insufficient treasury");
        (bool ok,) = payable(beneficiary).call{value: ethAmount}("");
        require(ok, "ETH transfer failed");
    }

    function _labelHash(string calldata label) internal pure returns (bytes32 result) {
        bytes memory labelBytes = bytes(label);
        assembly {
            result := keccak256(add(labelBytes, 32), mload(labelBytes))
        }
    }

    function _makeNode(bytes32 parentNode, bytes32 labelhash) internal pure returns (bytes32 result) {
        assembly {
            mstore(0x80, parentNode)
            mstore(0xa0, labelhash)
            result := keccak256(0x80, 64)
        }
    }

    function _register(
        bytes32 parentNode,
        string calldata label,
        address newOwner,
        address resolver,
        uint64 expiry,
        bytes[] calldata records
    ) internal {
        bytes32 labelhash = _labelHash(label);
        bytes32 node = _makeNode(parentNode, labelhash);
        if (!available(node)) revert Unavailable();

        uint32 fuses = PARENT_CANNOT_CONTROL;
        if (records.length > 0) {
            WRAPPER.setSubnodeOwner(parentNode, label, address(this), 0, expiry);
            _setRecords(node, resolver, records);
        }
        WRAPPER.setSubnodeRecord(
            parentNode,
            label,
            newOwner,
            resolver,
            0,
            fuses,
            expiry
        );
        emit NameRegistered(node, expiry);
    }

    function _setRecords(bytes32 node, address resolver, bytes[] calldata records) internal {
        for (uint256 i = 0; i < records.length; i++) {
            require(records[i].length >= 36, "Record too short");
            bytes32 txNamehash = bytes32(records[i][4:36]);
            require(txNamehash == node, "Namehash mismatch");
            resolver.functionCall(records[i]);
        }
    }

    function _renew(bytes32 parentNode, string calldata label, uint64 duration)
        internal
        returns (uint64 newExpiry)
    {
        bytes32 labelhash = _labelHash(label);
        bytes32 node = _makeNode(parentNode, labelhash);
        (,, uint64 expiry) = WRAPPER.getData(uint256(node));
        if (expiry < block.timestamp) revert NameNotRegistered();
        newExpiry = expiry + duration;
        WRAPPER.setChildFuses(parentNode, labelhash, 0, newExpiry);
        emit NameRenewed(node, newExpiry);
    }

    function _checkParent(bytes32 parentNode, uint64 duration) internal view {
        uint64 parentExpiry;
        try WRAPPER.getData(uint256(parentNode)) returns (address, uint32 fuses, uint64 expiry) {
            if (fuses & IS_DOT_ETH == IS_DOT_ETH) {
                expiry = expiry - GRACE_PERIOD;
            }
            if (block.timestamp > expiry) revert ParentExpired(parentNode);
            parentExpiry = expiry;
        } catch {
            revert ParentNotWrapped(parentNode);
        }
        if (uint256(block.timestamp) + duration > parentExpiry) revert DurationTooLong(parentNode);
    }
}
