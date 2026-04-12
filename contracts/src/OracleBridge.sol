// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

interface ICredoraScore {
    function writeScore(address wallet, uint256 score) external;
}

interface ISoulboundNFT {
    function mint(address to, string calldata scoreTier) external;
    function hasMinted(address wallet) external view returns (bool);
}

/**
 * @title OracleBridge
 * @notice Trusted bridge between the offchain ML scoring API and on-chain contracts
 * @dev Validates ECDSA signatures, prevents replay attacks, writes scores, and mints NFTs
 */
contract OracleBridge is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // State Variables

    /// @notice The ECDSA signer address from the backend oracle
    address public oracleSigner;

    /// @notice Reference to the CredoraScore contract
    ICredoraScore public credoraScore;

    /// @notice Reference to the SoulboundNFT contract
    ISoulboundNFT public soulboundNFT;

    /// @notice Tracks the last used nonce per wallet address
    mapping(address => uint256) public usedNonces;

    /// @notice Maximum age for a score payload timestamp (5 minutes)
    uint256 public constant MAX_PAYLOAD_AGE = 5 minutes;

    // Events

    /// @notice Emitted when a score is processed and written on-chain
    /// @param wallet The wallet address that was scored
    /// @param score The credit score (0-10000)
    /// @param nonce The nonce used for this score
    /// @param nftMinted Whether a new NFT was minted
    event ScoreProcessed(
        address indexed wallet,
        uint256 score,
        uint256 nonce,
        bool nftMinted
    );

    /// @notice Emitted when the oracle signer is updated
    /// @param oldSigner The previous signer address
    /// @param newSigner The new signer address
    event OracleSignerUpdated(address indexed oldSigner, address indexed newSigner);

    // Errors

    error ScoreOutOfRange();
    error NonceAlreadyUsed();
    error PayloadExpired();
    error InvalidSignature();
    error ZeroAddress();

    // Constructor

    /**
     * @notice Initializes the oracle bridge with contract references
     * @param _oracleSigner The ECDSA signer address from the backend
     * @param _credoraScore The CredoraScore contract address
     * @param _soulboundNFT The SoulboundNFT contract address
     */
    constructor(
        address _oracleSigner,
        address _credoraScore,
        address _soulboundNFT
    ) Ownable(msg.sender) {
        if (_oracleSigner == address(0)) revert ZeroAddress();
        if (_credoraScore == address(0)) revert ZeroAddress();
        if (_soulboundNFT == address(0)) revert ZeroAddress();

        oracleSigner = _oracleSigner;
        credoraScore = ICredoraScore(_credoraScore);
        soulboundNFT = ISoulboundNFT(_soulboundNFT);
    }

    // External Functions

    /**
     * @notice Processes a signed score payload from the backend oracle
     * @dev Follows checks-effects-interactions pattern strictly
     * @param wallet The wallet address being scored
     * @param score The credit score (0-10000)
     * @param nonce The nonce for replay protection (must be > last used)
     * @param timestamp The Unix timestamp when the score was computed
     * @param signature The ECDSA signature from the oracle backend
     */
    function processScore(
        address wallet,
        uint256 score,
        uint256 nonce,
        uint256 timestamp,
        bytes calldata signature
    ) external nonReentrant {
        // CHECKS

        // Validate score range
        if (score > 10000) revert ScoreOutOfRange();

        // Validate nonce (must be strictly greater than last used)
        if (nonce <= usedNonces[wallet]) revert NonceAlreadyUsed();

        // Validate timestamp (must be within 5 minutes)
        if (block.timestamp - timestamp > MAX_PAYLOAD_AGE) revert PayloadExpired();

        // Verify ECDSA signature
        bytes32 messageHash = keccak256(abi.encodePacked(wallet, score, nonce, timestamp));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address recoveredSigner = ethSignedMessageHash.recover(signature);

        if (recoveredSigner != oracleSigner) revert InvalidSignature();

        // EFFECTS

        // Mark nonce as used
        usedNonces[wallet] = nonce;

        // INTERACTIONS

        // Write score to CredoraScore contract
        credoraScore.writeScore(wallet, score);

        // Mint NFT if wallet hasn't minted yet
        bool nftMinted = false;
        if (!soulboundNFT.hasMinted(wallet)) {
            string memory scoreTier = _getScoreTier(score);
            soulboundNFT.mint(wallet, scoreTier);
            nftMinted = true;
        }

        emit ScoreProcessed(wallet, score, nonce, nftMinted);
    }

    /**
     * @notice Updates the oracle signer address
     * @dev Only callable by contract owner
     * @param newSigner The new oracle signer address
     */
    function setOracleSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert ZeroAddress();

        address oldSigner = oracleSigner;
        oracleSigner = newSigner;

        emit OracleSignerUpdated(oldSigner, newSigner);
    }

    /**
     * @notice Updates the CredoraScore contract reference
     * @dev Only callable by contract owner
     * @param addr The new CredoraScore contract address
     */
    function setCredoraScore(address addr) external onlyOwner {
        if (addr == address(0)) revert ZeroAddress();
        credoraScore = ICredoraScore(addr);
    }

    /**
     * @notice Updates the SoulboundNFT contract reference
     * @dev Only callable by contract owner
     * @param addr The new SoulboundNFT contract address
     */
    function setSoulboundNFT(address addr) external onlyOwner {
        if (addr == address(0)) revert ZeroAddress();
        soulboundNFT = ISoulboundNFT(addr);
    }

    // Internal Functions

    /**
     * @notice Derives the score tier label from a numeric score
     * @dev Score ranges: 0-1999=DEVELOPING, 2000-3999=FAIR, 4000-5999=GOOD,
     *      6000-7999=STRONG, 8000-10000=EXCEPTIONAL
     * @param score The numeric score (0-10000)
     * @return The tier label string
     */
    function _getScoreTier(uint256 score) internal pure returns (string memory) {
        if (score < 2000) return "DEVELOPING";
        if (score < 4000) return "FAIR";
        if (score < 6000) return "GOOD";
        if (score < 8000) return "STRONG";
        return "EXCEPTIONAL";
    }

    // Public View Functions

    /**
     * @notice Gets the score tier label for a given numeric score
     * @dev Public wrapper for _getScoreTier for external queries
     * @param score The numeric score (0-10000)
     * @return The tier label string
     */
    function getScoreTier(uint256 score) public pure returns (string memory) {
        return _getScoreTier(score);
    }
}
