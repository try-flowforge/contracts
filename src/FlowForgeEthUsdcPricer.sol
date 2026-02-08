// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFlowForgeSubdomainPricer} from "./interfaces/IFlowForgeSubdomainPricer.sol";
import {IFlowForgeSubdomainPricerMultiToken} from "./interfaces/IFlowForgeSubdomainPricerMultiToken.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";

error DurationNotWholeWeeks();

/**
 * @title FlowForgeEthUsdcPricer
 * @notice Accept ETH or USDC: 0.5 USDC per 1 week of subdomain expiry. ETH price via Chainlink ETH/USD.
 * @dev Price is always a multiple of 0.5 USDC; duration must be a whole number of weeks.
 *      Use registerWithToken(..., address(0)) to pay in ETH, registerWithToken(..., USDC) to pay in USDC.
 */
contract FlowForgeEthUsdcPricer is IFlowForgeSubdomainPricer, IFlowForgeSubdomainPricerMultiToken {
    /// 1 week in seconds
    uint256 public constant PERIOD_SECONDS = 7 * 24 * 3600; // 604_800
    /// 0.5 USDC (6 decimals) per period
    uint256 public constant PRICE_PER_PERIOD = 5 * 10 ** 5; // 0.5e6

    address public immutable USDC;
    IAggregatorV3 public immutable ETH_USD_FEED;

    constructor(address usdc_, address ethUsdFeed_) {
        require(usdc_ != address(0), "Zero USDC");
        require(ethUsdFeed_ != address(0), "Zero feed");
        USDC = usdc_;
        ETH_USD_FEED = IAggregatorV3(ethUsdFeed_);
    }

    /// @inheritdoc IFlowForgeSubdomainPricer
    function price(
        bytes32 /* parentNode */,
        string calldata /* label */,
        uint256 duration
    ) external view returns (address token, uint256 priceAmount) {
        token = USDC;
        priceAmount = _usdcPrice(duration);
    }

    /// @inheritdoc IFlowForgeSubdomainPricerMultiToken
    function priceForToken(
        bytes32 /* parentNode */,
        string calldata /* label */,
        uint256 duration,
        address paymentToken
    ) external view returns (uint256 priceAmount) {
        if (paymentToken == address(0)) {
            return _ethPrice(duration);
        }
        if (paymentToken == USDC) {
            return _usdcPrice(duration);
        }
        revert("Unsupported payment token");
    }

    function _usdcPrice(uint256 duration) internal pure returns (uint256) {
        if (duration == 0 || duration % PERIOD_SECONDS != 0) revert DurationNotWholeWeeks();
        return (duration * PRICE_PER_PERIOD) / PERIOD_SECONDS;
    }

    /// @dev ETH/USD feed has 8 decimals. USDC amount (6 decimals) = USD value. wei = usdValue * 1e18 / (price * 1e8)
    function _ethPrice(uint256 duration) internal view returns (uint256) {
        uint256 usdcAmount = _usdcPrice(duration);
        (, int256 answer,,,) = ETH_USD_FEED.latestRoundData();
        require(answer > 0, "Invalid price");
        // casting to uint256 is safe because we require answer > 0 above
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 ethUsd8 = uint256(int256(answer));
        // wei = (usdcAmount / 1e6) * 1e18 / (ethUsd8 / 1e8) = usdcAmount * 1e20 / ethUsd8
        return (usdcAmount * 1e20) / ethUsd8;
    }
}
