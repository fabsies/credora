// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title SoulboundNFT
 * @notice Non-transferable ERC721 credential NFT minted once per wallet as proof of Credora score
 * @dev Overrides _update to enforce soulbound guarantee (OZ v5 pattern)
 */
contract SoulboundNFT is ERC721, Ownable {
    using Strings for uint256;

    // State Variables

    /// @notice Token ID counter, starts at 1
    uint256 private _tokenIdCounter = 1;

    /// @notice Tracks which addresses have already minted
    mapping(address => bool) public hasMinted;

    /// @notice The authorized minter address (oracle bridge)
    address public authorizedMinter;

    /// @notice Maps token ID to score tier string
    mapping(uint256 => string) private _tokenScoreTier;

    // Events

    /// @notice Emitted when a credential NFT is minted
    /// @param to The recipient wallet address
    /// @param tokenId The minted token ID
    /// @param scoreTier The score tier label (e.g., "EXCEPTIONAL")
    event Minted(address indexed to, uint256 indexed tokenId, string scoreTier);

    /// @notice Emitted when the authorized minter is updated
    /// @param oldMinter The previous minter address
    /// @param newMinter The new minter address
    event MinterUpdated(address indexed oldMinter, address indexed newMinter);

    // Errors

    error NotMinter();
    error AlreadyMinted();
    error NonTransferable();
    error ZeroAddress();

    // Modifiers

    /// @notice Restricts function access to authorized minter only
    modifier onlyMinter() {
        if (msg.sender != authorizedMinter) revert NotMinter();
        _;
    }

    // Constructor

    /// @notice Initializes the soulbound NFT contract
    /// @param _authorizedMinter The address authorized to mint NFTs
    constructor(address _authorizedMinter)
        ERC721("Credora Credit Credential", "CREDORA")
        Ownable(msg.sender)
    {
        if (_authorizedMinter == address(0)) revert ZeroAddress();
        authorizedMinter = _authorizedMinter;
    }

    // External Functions

    /**
     * @notice Mints a soulbound credential NFT to a wallet
     * @dev Only callable by authorized minter, enforces one NFT per wallet
     * @param to The wallet address to receive the NFT
     * @param scoreTier The score tier label (e.g., "GOOD", "EXCEPTIONAL")
     */
    function mint(address to, string calldata scoreTier) external onlyMinter {
        if (hasMinted[to]) revert AlreadyMinted();

        uint256 newTokenId = _tokenIdCounter;
        _tokenIdCounter++;

        hasMinted[to] = true;
        _tokenScoreTier[newTokenId] = scoreTier;

        _safeMint(to, newTokenId);

        emit Minted(to, newTokenId, scoreTier);
    }

    /**
     * @notice Updates the authorized minter address
     * @dev Only callable by contract owner
     * @param newMinter The new minter address
     */
    function setMinter(address newMinter) external onlyOwner {
        if (newMinter == address(0)) revert ZeroAddress();

        address oldMinter = authorizedMinter;
        authorizedMinter = newMinter;

        emit MinterUpdated(oldMinter, newMinter);
    }

    // Public View Functions

    /**
     * @notice Returns the score tier for a given token ID
     * @param tokenId The token ID to query
     * @return The score tier string
     */
    function getScoreTier(uint256 tokenId) public view returns (string memory) {
        _requireOwned(tokenId);
        return _tokenScoreTier[tokenId];
    }

    /**
     * @notice Returns the on-chain JSON metadata for a token
     * @param tokenId The token ID to query
     * @return Base64-encoded JSON metadata URI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        string memory tier = _tokenScoreTier[tokenId];
        address owner = ownerOf(tokenId);

        string memory json = string(
            abi.encodePacked(
                '{"name": "Credora Credit Credential #',
                tokenId.toString(),
                '", "description": "Non-transferable proof of on-chain creditworthiness", "attributes": [{"trait_type": "Score Tier", "value": "',
                tier,
                '"}, {"trait_type": "Wallet", "value": "',
                _addressToString(owner),
                '"}]}'
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    // Internal Functions

    /**
     * @notice Enforces the soulbound guarantee by blocking all transfers
     * @dev Overrides ERC721 _update to revert on any transfer (OZ v5 pattern)
     * @param to The destination address
     * @param tokenId The token ID being transferred
     * @param auth The authorized operator
     * @return The previous owner address
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);

        // Allow mints (from == address(0)) but block all transfers
        if (from != address(0)) {
            revert NonTransferable();
        }

        return super._update(to, tokenId, auth);
    }

    /**
     * @notice Converts an address to a lowercase hex string
     * @param addr The address to convert
     * @return The address as a string
     */
    function _addressToString(address addr) private pure returns (string memory) {
        bytes memory data = abi.encodePacked(addr);
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }

        return string(str);
    }

    // Override Approval Functions

    /**
     * @notice Disables approve functionality for soulbound tokens
     * @dev Always reverts to prevent any approval attempts
     */
    function approve(address, uint256) public pure override {
        revert NonTransferable();
    }

    /**
     * @notice Disables setApprovalForAll functionality for soulbound tokens
     * @dev Always reverts to prevent any approval attempts
     */
    function setApprovalForAll(address, bool) public pure override {
        revert NonTransferable();
    }
}
