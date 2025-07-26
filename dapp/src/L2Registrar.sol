// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StringUtils} from "@ensdomains/ens-contracts/utils/StringUtils.sol";
import {IL2Registry} from "@durin/contracts/interfaces/IL2Registry.sol";

contract L2Registrar {
    using StringUtils for string;

    /// @notice The account with permission to add/modify names
    address public admin;

    /// @notice Emitted when a new name is registered or modified
    /// @param label The registered label (e.g. "name" in "name.eth")
    /// @param owner The owner of the newly registered name
    event NameRegistered(string indexed label, address indexed owner);

    /// @notice Reference to the target registry contract
    IL2Registry public immutable registry;

    /// @notice The chainId for the current chain
    uint256 public chainId;

    /// @notice The coinType for the current chain (ENSIP-11)
    uint256 public immutable coinType;

    /// @notice Initializes the registrar with a registry contract and sets the admin.
    /// @param _registry Address of the L2Registry contract
    constructor(address _registry) {
        // Set the deployer as the admin
        admin = msg.sender;

        // Save the chainId in memory (accessed via assembly)
        assembly {
            sstore(chainId.slot, chainid())
        }

        // Calculate the coinType for the current chain according to ENSIP-11
        coinType = (0x80000000 | chainId) >> 0;

        // Save the registry address
        registry = IL2Registry(_registry);
    }

    /// @dev Modifier that allows only the admin to call a function.
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can modify registry");
        _;
    }

    /// @notice Registers a new name. Only the admin can call this function.
    /// @param label The label to register (e.g. "name" for "name.eth")
    /// @param owner The address that will own the name
    function register(string calldata label, address owner) external onlyAdmin {
        bytes32 node = _labelToNode(label);
        bytes memory addr = abi.encodePacked(owner); // Convert address to bytes

        // Set the forward address for the current chain. This is needed for reverse resolution.
        // E.g. if this contract is deployed to Base, set an address for chainId 8453 which is
        // coinType 2147492101 according to ENSIP-11.
        registry.setAddr(node, coinType, addr);

        // Set the forward address for mainnet ETH (coinType 60) for easier debugging.
        registry.setAddr(node, 60, addr);

        // Register the name in the L2 registry
        registry.createSubnode(
            registry.baseNode(),
            label,
            owner,
            new bytes[](0)
        );
        emit NameRegistered(label, owner);
    }

    /// @notice Checks if a given label is available for registration
    /// @dev Uses try-catch to handle the ERC721NonexistentToken error
    /// @param label The label to check availability for
    /// @return available True if the label can be registered, false if already taken
    function available(string calldata label) external view returns (bool) {
        bytes32 node = _labelToNode(label);
        uint256 tokenId = uint256(node);

        try registry.ownerOf(tokenId) {
            return false;
        } catch {
            if (label.strlen() >= 3) {
                return true;
            }
            return false;
        }
    }

    function _labelToNode(
        string calldata label
    ) private view returns (bytes32) {
        return registry.makeNode(registry.baseNode(), label);
    }
    
    /// @notice Allows the admin to change the admin account.
    /// @param newAdmin The new admin address.
    function updateAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid admin address");
        admin = newAdmin;
    }

}
