// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CredoraScore
 * @notice Stores ML-computed credit scores (0-10000 range) with timestamps per wallet address
 * @dev Only the authorized oracle can write scores. Owner can update the oracle address.
 */
contract CredoraScore is Ownable {
    // State Variables

    /// @notice Mapping of wallet address to credit score (0-10000)
    mapping(address => uint256) private scores;

    /// @notice Mapping of wallet address to score update timestamp
    mapping(address => uint256) private scoreTimestamps;

    /// @notice The authorized oracle address that can write scores
    address public authorizedOracle;

    // Events

    /// @notice Emitted when a score is updated
    /// @param wallet The wallet address whose score was updated
    /// @param score The new credit score (0-10000)
    /// @param timestamp The block timestamp of the update
    event ScoreUpdated(address indexed wallet, uint256 score, uint256 timestamp);

    /// @notice Emitted when the authorized oracle is updated
    /// @param oldOracle The previous oracle address
    /// @param newOracle The new oracle address
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    // Errors

    error NotOracle();
    error ScoreOutOfRange();
    error ZeroAddress();

    // Modifiers

    /// @notice Restricts function access to authorized oracle only
    modifier onlyOracle() {
        if (msg.sender != authorizedOracle) revert NotOracle();
        _;
    }

    // Constructor

    /// @notice Initializes the contract with the authorized oracle address
    /// @param _authorizedOracle The address authorized to write scores
    constructor(address _authorizedOracle) Ownable(msg.sender) {
        if (_authorizedOracle == address(0)) revert ZeroAddress();
        authorizedOracle = _authorizedOracle;
    }

    // External Functions

    /**
     * @notice Writes a credit score for a wallet address
     * @dev Only callable by the authorized oracle
     * @param wallet The wallet address to score
     * @param score The credit score (0-10000)
     */
    function writeScore(address wallet, uint256 score) external onlyOracle {
        if (score > 10000) revert ScoreOutOfRange();

        scores[wallet] = score;
        scoreTimestamps[wallet] = block.timestamp;

        emit ScoreUpdated(wallet, score, block.timestamp);
    }

    /**
     * @notice Updates the authorized oracle address
     * @dev Only callable by contract owner
     * @param newOracle The new oracle address
     */
    function setOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert ZeroAddress();

        address oldOracle = authorizedOracle;
        authorizedOracle = newOracle;

        emit OracleUpdated(oldOracle, newOracle);
    }

    // Public View Functions

    /**
     * @notice Retrieves the score and timestamp for a wallet
     * @param wallet The wallet address to query
     * @return score The credit score (0 if never scored)
     * @return timestamp The last update timestamp (0 if never scored)
     */
    function getScore(address wallet) public view returns (uint256 score, uint256 timestamp) {
        return (scores[wallet], scoreTimestamps[wallet]);
    }

    /**
     * @notice Checks if a wallet's score is fresh (within maxAge seconds)
     * @param wallet The wallet address to check
     * @param maxAge Maximum age in seconds for a score to be considered fresh
     * @return bool True if score exists and is within maxAge, false otherwise
     */
    function isScoreFresh(address wallet, uint256 maxAge) public view returns (bool) {
        uint256 timestamp = scoreTimestamps[wallet];
        if (timestamp == 0) return false;
        return (block.timestamp - timestamp) <= maxAge;
    }
}
