// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/OracleBridge.sol";
import "../src/CredoraScore.sol";
import "../src/SoulboundNFT.sol";

contract OracleBridgeTest is Test {
    OracleBridge public bridge;
    CredoraScore public scoreContract;
    SoulboundNFT public nftContract;

    address public owner;
    address public oracleSigner;
    uint256 public oraclePrivateKey;
    address public wrongSigner;
    uint256 public wrongPrivateKey;
    address public testWallet;

    event ScoreProcessed(
        address indexed wallet,
        uint256 score,
        uint256 nonce,
        bool nftMinted
    );
    event OracleSignerUpdated(address indexed oldSigner, address indexed newSigner);

    function setUp() public {
        owner = address(this);
        testWallet = makeAddr("testWallet");

        // Create oracle signer keypair
        oraclePrivateKey = 0xA11CE;
        oracleSigner = vm.addr(oraclePrivateKey);

        // Create wrong signer keypair for negative tests
        wrongPrivateKey = 0xBAD;
        wrongSigner = vm.addr(wrongPrivateKey);

        // Deploy contracts
        scoreContract = new CredoraScore(address(1)); // Temporary oracle
        nftContract = new SoulboundNFT(address(1)); // Temporary minter

        bridge = new OracleBridge(oracleSigner, address(scoreContract), address(nftContract));

        // Set bridge as authorized oracle and minter
        scoreContract.setOracle(address(bridge));
        nftContract.setMinter(address(bridge));
    }

    // Helper Functions

    function _createSignature(
        address wallet,
        uint256 score,
        uint256 nonce,
        uint256 timestamp,
        uint256 privateKey
    ) internal pure returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(wallet, score, nonce, timestamp));
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }

    // Constructor Tests

    function test_Constructor_Success() public view {
        assertEq(bridge.oracleSigner(), oracleSigner);
        assertEq(address(bridge.credoraScore()), address(scoreContract));
        assertEq(address(bridge.soulboundNFT()), address(nftContract));
        assertEq(bridge.owner(), owner);
    }

    function test_Constructor_RevertsOnZeroOracleSigner() public {
        vm.expectRevert(OracleBridge.ZeroAddress.selector);
        new OracleBridge(address(0), address(scoreContract), address(nftContract));
    }

    function test_Constructor_RevertsOnZeroCredoraScore() public {
        vm.expectRevert(OracleBridge.ZeroAddress.selector);
        new OracleBridge(oracleSigner, address(0), address(nftContract));
    }

    function test_Constructor_RevertsOnZeroSoulboundNFT() public {
        vm.expectRevert(OracleBridge.ZeroAddress.selector);
        new OracleBridge(oracleSigner, address(scoreContract), address(0));
    }

    // processScore Tests (Happy Path)

    function test_ProcessScore_Success() public {
        uint256 score = 7500;
        uint256 nonce = 1;
        uint256 timestamp = block.timestamp;

        bytes memory signature = _createSignature(
            testWallet,
            score,
            nonce,
            timestamp,
            oraclePrivateKey
        );

        vm.expectEmit(true, false, false, true);
        emit ScoreProcessed(testWallet, score, nonce, true);

        bridge.processScore(testWallet, score, nonce, timestamp, signature);

        // Verify score was written
        (uint256 storedScore,) = scoreContract.getScore(testWallet);
        assertEq(storedScore, score);

        // Verify NFT was minted
        assertTrue(nftContract.hasMinted(testWallet));
        assertEq(nftContract.balanceOf(testWallet), 1);

        // Verify nonce was updated
        assertEq(bridge.usedNonces(testWallet), nonce);
    }

    function test_ProcessScore_WritesScoreToContract() public {
        uint256 score = 5432;
        uint256 nonce = 1;
        uint256 timestamp = block.timestamp;

        bytes memory signature = _createSignature(
            testWallet,
            score,
            nonce,
            timestamp,
            oraclePrivateKey
        );

        bridge.processScore(testWallet, score, nonce, timestamp, signature);

        (uint256 storedScore, uint256 storedTimestamp) = scoreContract.getScore(testWallet);
        assertEq(storedScore, score);
        assertEq(storedTimestamp, block.timestamp);
    }

    function test_ProcessScore_MintsNFTWithCorrectTier() public {
        uint256 score = 8500; // EXCEPTIONAL tier
        uint256 nonce = 1;
        uint256 timestamp = block.timestamp;

        bytes memory signature = _createSignature(
            testWallet,
            score,
            nonce,
            timestamp,
            oraclePrivateKey
        );

        bridge.processScore(testWallet, score, nonce, timestamp, signature);

        assertEq(nftContract.getScoreTier(1), "EXCEPTIONAL");
    }

    function test_ProcessScore_NoNFTRemint() public {
        uint256 nonce = 1;
        uint256 timestamp = block.timestamp;

        // First score
        bytes memory signature1 = _createSignature(
            testWallet,
            5000,
            nonce,
            timestamp,
            oraclePrivateKey
        );

        vm.expectEmit(true, false, false, true);
        emit ScoreProcessed(testWallet, 5000, nonce, true); // nftMinted = true

        bridge.processScore(testWallet, 5000, nonce, timestamp, signature1);

        // Second score (update)
        nonce = 2;
        timestamp = block.timestamp;

        bytes memory signature2 = _createSignature(
            testWallet,
            8000,
            nonce,
            timestamp,
            oraclePrivateKey
        );

        vm.expectEmit(true, false, false, true);
        emit ScoreProcessed(testWallet, 8000, nonce, false); // nftMinted = false

        bridge.processScore(testWallet, 8000, nonce, timestamp, signature2);

        // Should still only have 1 NFT
        assertEq(nftContract.balanceOf(testWallet), 1);

        // Score should be updated
        (uint256 storedScore,) = scoreContract.getScore(testWallet);
        assertEq(storedScore, 8000);
    }

    // processScore Tests (Validation Failures)

    function test_ProcessScore_Revert_ScoreOutOfRange() public {
        uint256 score = 10001;
        uint256 nonce = 1;
        uint256 timestamp = block.timestamp;

        bytes memory signature = _createSignature(
            testWallet,
            score,
            nonce,
            timestamp,
            oraclePrivateKey
        );

        vm.expectRevert(OracleBridge.ScoreOutOfRange.selector);
        bridge.processScore(testWallet, score, nonce, timestamp, signature);
    }

    function test_ProcessScore_Revert_UsedNonce() public {
        uint256 score = 7000;
        uint256 nonce = 1;
        uint256 timestamp = block.timestamp;

        bytes memory signature = _createSignature(
            testWallet,
            score,
            nonce,
            timestamp,
            oraclePrivateKey
        );

        // First call succeeds
        bridge.processScore(testWallet, score, nonce, timestamp, signature);

        // Second call with same nonce reverts
        vm.expectRevert(OracleBridge.NonceAlreadyUsed.selector);
        bridge.processScore(testWallet, score, nonce, timestamp, signature);
    }

    function test_ProcessScore_Revert_ExpiredTimestamp() public {
        uint256 score = 7000;
        uint256 nonce = 1;
        uint256 timestamp = block.timestamp;

        bytes memory signature = _createSignature(
            testWallet,
            score,
            nonce,
            timestamp,
            oraclePrivateKey
        );

        // Warp time forward beyond 5 minutes
        vm.warp(block.timestamp + 6 minutes);

        vm.expectRevert(OracleBridge.PayloadExpired.selector);
        bridge.processScore(testWallet, score, nonce, timestamp, signature);
    }

    function test_ProcessScore_Revert_InvalidSignature() public {
        uint256 score = 7000;
        uint256 nonce = 1;
        uint256 timestamp = block.timestamp;

        // Sign with wrong private key
        bytes memory signature = _createSignature(
            testWallet,
            score,
            nonce,
            timestamp,
            wrongPrivateKey
        );

        vm.expectRevert(OracleBridge.InvalidSignature.selector);
        bridge.processScore(testWallet, score, nonce, timestamp, signature);
    }

    function test_ProcessScore_AcceptsMaxPayloadAge() public {
        uint256 score = 7000;
        uint256 nonce = 1;
        uint256 timestamp = block.timestamp;

        bytes memory signature = _createSignature(
            testWallet,
            score,
            nonce,
            timestamp,
            oraclePrivateKey
        );

        // Warp to exactly 5 minutes (should still be valid)
        vm.warp(block.timestamp + 5 minutes);

        bridge.processScore(testWallet, score, nonce, timestamp, signature);

        (uint256 storedScore,) = scoreContract.getScore(testWallet);
        assertEq(storedScore, score);
    }

    // Nonce Monotonicity Tests

    function test_ProcessScore_NonceMustIncrease() public {
        uint256 score = 7000;
        uint256 timestamp = block.timestamp;

        // Process with nonce 1
        bytes memory sig1 = _createSignature(testWallet, score, 1, timestamp, oraclePrivateKey);
        bridge.processScore(testWallet, score, 1, timestamp, sig1);

        // Try to process with nonce 1 again (same nonce)
        vm.expectRevert(OracleBridge.NonceAlreadyUsed.selector);
        bridge.processScore(testWallet, score, 1, timestamp, sig1);

        // Nonce 2 should work
        timestamp = block.timestamp;
        bytes memory sig2 = _createSignature(testWallet, score, 2, timestamp, oraclePrivateKey);
        bridge.processScore(testWallet, score, 2, timestamp, sig2);

        assertEq(bridge.usedNonces(testWallet), 2);
    }

    function test_ProcessScore_CannotSkipBackwardsInNonce() public {
        uint256 score = 7000;
        uint256 timestamp = block.timestamp;

        // Process with nonce 5
        bytes memory sig5 = _createSignature(testWallet, score, 5, timestamp, oraclePrivateKey);
        bridge.processScore(testWallet, score, 5, timestamp, sig5);

        // Try to use nonce 3 (lower than last used)
        timestamp = block.timestamp;
        bytes memory sig3 = _createSignature(testWallet, score, 3, timestamp, oraclePrivateKey);

        vm.expectRevert(OracleBridge.NonceAlreadyUsed.selector);
        bridge.processScore(testWallet, score, 3, timestamp, sig3);
    }

    // Score Tier Mapping Tests

    function test_GetScoreTier_Developing() public view {
        assertEq(bridge.getScoreTier(0), "DEVELOPING");
        assertEq(bridge.getScoreTier(1000), "DEVELOPING");
        assertEq(bridge.getScoreTier(1999), "DEVELOPING");
    }

    function test_GetScoreTier_Fair() public view {
        assertEq(bridge.getScoreTier(2000), "FAIR");
        assertEq(bridge.getScoreTier(3000), "FAIR");
        assertEq(bridge.getScoreTier(3999), "FAIR");
    }

    function test_GetScoreTier_Good() public view {
        assertEq(bridge.getScoreTier(4000), "GOOD");
        assertEq(bridge.getScoreTier(5000), "GOOD");
        assertEq(bridge.getScoreTier(5999), "GOOD");
    }

    function test_GetScoreTier_Strong() public view {
        assertEq(bridge.getScoreTier(6000), "STRONG");
        assertEq(bridge.getScoreTier(7000), "STRONG");
        assertEq(bridge.getScoreTier(7999), "STRONG");
    }

    function test_GetScoreTier_Exceptional() public view {
        assertEq(bridge.getScoreTier(8000), "EXCEPTIONAL");
        assertEq(bridge.getScoreTier(9000), "EXCEPTIONAL");
        assertEq(bridge.getScoreTier(10000), "EXCEPTIONAL");
    }

    // Admin Function Tests

    function test_SetOracleSigner_Success() public {
        address newSigner = makeAddr("newSigner");

        vm.expectEmit(true, true, false, false);
        emit OracleSignerUpdated(oracleSigner, newSigner);

        bridge.setOracleSigner(newSigner);

        assertEq(bridge.oracleSigner(), newSigner);
    }

    function test_SetOracleSigner_OnlyOwner() public {
        address newSigner = makeAddr("newSigner");
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        bridge.setOracleSigner(newSigner);
    }

    function test_SetOracleSigner_RevertsOnZeroAddress() public {
        vm.expectRevert(OracleBridge.ZeroAddress.selector);
        bridge.setOracleSigner(address(0));
    }

    function test_SetCredoraScore_Success() public {
        CredoraScore newScore = new CredoraScore(address(bridge));
        bridge.setCredoraScore(address(newScore));

        assertEq(address(bridge.credoraScore()), address(newScore));
    }

    function test_SetCredoraScore_RevertsOnZeroAddress() public {
        vm.expectRevert(OracleBridge.ZeroAddress.selector);
        bridge.setCredoraScore(address(0));
    }

    function test_SetSoulboundNFT_Success() public {
        SoulboundNFT newNFT = new SoulboundNFT(address(bridge));
        bridge.setSoulboundNFT(address(newNFT));

        assertEq(address(bridge.soulboundNFT()), address(newNFT));
    }

    function test_SetSoulboundNFT_RevertsOnZeroAddress() public {
        vm.expectRevert(OracleBridge.ZeroAddress.selector);
        bridge.setSoulboundNFT(address(0));
    }

    // Integration Tests

    function test_Integration_FullScoreFlow() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        // User 1: DEVELOPING tier (score 1500)
        bytes memory sig1 = _createSignature(user1, 1500, 1, block.timestamp, oraclePrivateKey);
        bridge.processScore(user1, 1500, 1, block.timestamp, sig1);

        assertEq(nftContract.getScoreTier(1), "DEVELOPING");
        (uint256 score1,) = scoreContract.getScore(user1);
        assertEq(score1, 1500);

        // User 2: EXCEPTIONAL tier (score 9000)
        bytes memory sig2 = _createSignature(user2, 9000, 1, block.timestamp, oraclePrivateKey);
        bridge.processScore(user2, 9000, 1, block.timestamp, sig2);

        assertEq(nftContract.getScoreTier(2), "EXCEPTIONAL");
        (uint256 score2,) = scoreContract.getScore(user2);
        assertEq(score2, 9000);
    }

    function test_Integration_ScoreUpdateWithoutRemint() public {
        // Initial score
        bytes memory sig1 = _createSignature(
            testWallet,
            3000,
            1,
            block.timestamp,
            oraclePrivateKey
        );
        bridge.processScore(testWallet, 3000, 1, block.timestamp, sig1);

        uint256 initialTokenId = 1;
        assertEq(nftContract.getScoreTier(initialTokenId), "FAIR");

        // Update score
        uint256 newTimestamp = block.timestamp;
        bytes memory sig2 = _createSignature(testWallet, 9000, 2, newTimestamp, oraclePrivateKey);
        bridge.processScore(testWallet, 9000, 2, newTimestamp, sig2);

        // Score updated
        (uint256 updatedScore,) = scoreContract.getScore(testWallet);
        assertEq(updatedScore, 9000);

        // Still only 1 NFT, but original tier unchanged (NFTs are immutable)
        assertEq(nftContract.balanceOf(testWallet), 1);
        assertEq(nftContract.getScoreTier(initialTokenId), "FAIR"); // Original tier preserved
    }

    // Fuzz Tests

    function testFuzz_ProcessScore_ValidScores(uint256 score) public {
        score = bound(score, 0, 10000);

        uint256 nonce = 1;
        uint256 timestamp = block.timestamp;

        bytes memory signature = _createSignature(
            testWallet,
            score,
            nonce,
            timestamp,
            oraclePrivateKey
        );

        bridge.processScore(testWallet, score, nonce, timestamp, signature);

        (uint256 storedScore,) = scoreContract.getScore(testWallet);
        assertEq(storedScore, score);
    }

    function testFuzz_ProcessScore_MonotonicNonces(uint8 nonceCount) public {
        nonceCount = uint8(bound(nonceCount, 1, 20));

        for (uint256 i = 1; i <= nonceCount; i++) {
            uint256 timestamp = block.timestamp;
            bytes memory sig = _createSignature(
                testWallet,
                5000,
                i,
                timestamp,
                oraclePrivateKey
            );

            bridge.processScore(testWallet, 5000, i, timestamp, sig);
            assertEq(bridge.usedNonces(testWallet), i);
        }
    }
}
