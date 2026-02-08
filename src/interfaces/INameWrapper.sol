// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title INameWrapper
 * @notice Minimal interface for ENS Name Wrapper used by FlowForgeSubdomainRegistry.
 * @dev See https://docs.ens.domains/contract-api-reference/name-wrapper
 *      Mainnet: 0xd4416b13d2b3a9abae7acd5d6c2bbdbe25686401
 */
interface INameWrapper {
    function setSubnodeRecord(
        bytes32 parentNode,
        string calldata label,
        address owner,
        address resolver,
        uint64 ttl,
        uint32 fuses,
        uint64 expiry
    ) external returns (bytes32);

    function setSubnodeOwner(
        bytes32 parentNode,
        string calldata label,
        address owner,
        uint32 fuses,
        uint64 expiry
    ) external returns (bytes32);

    /// @notice Set fuses and expiry on an existing child (e.g. for renewals).
    function setChildFuses(
        bytes32 parentNode,
        bytes32 labelhash,
        uint32 fuses,
        uint64 expiry
    ) external;

    function getData(uint256 id) external view returns (address owner, uint32 fuses, uint64 expiry);

    function canModifyName(bytes32 node, address addr) external view returns (bool);
}
