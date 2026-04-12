// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/CredoraScore.sol";

contract CredoraScoreTest is Test {
    CredoraScore public credoraScore;

    address public owner;
    address public oracle;
    address public nonOracle;
    address public testWallet;

    event ScoreUpdated(address indexed wallet, uint256 score, uint256 timestamp);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    function setUp() public {
        owner = address(this);
        oracle = makeAddr("oracle");
        nonOracle = makeAddr("nonOracle");
        testWallet = makeAddr("testWallet");

        credoraScore = new CredoraScore(oracle);
    }

    // Constructor Tests

    function test_Constructor_Success() public view {
        assertEq(credoraScore.authorizedOracle(), oracle);
        assertEq(credoraScore.owner(), owner);
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        vm.expectRevert(CredoraScore.ZeroAddress.selector);
        new CredoraScore(address(0));
    }

    // writeScore Tests

    function test_WriteScore_Success() public {
        uint256 score = 7500;

        vm.expectEmit(true, false, false, true);
        emit ScoreUpdated(testWallet, score, block.timestamp);

        vm.prank(oracle);
        credoraScore.writeScore(testWallet, score);

        (uint256 storedScore, uint256 timestamp) = credoraScore.getScore(testWallet);
        assertEq(storedScore, score);
        assertEq(timestamp, block.timestamp);
    }

    function test_WriteScore_UpdatesExistingScore() public {
        vm.startPrank(oracle);

        // First write
        credoraScore.writeScore(testWallet, 5000);
        (uint256 firstScore, uint256 firstTimestamp) = credoraScore.getScore(testWallet);
        assertEq(firstScore, 5000);

        // Advance time
        vm.warp(block.timestamp + 1 days);

        // Second write (update)
        credoraScore.writeScore(testWallet, 8000);
        (uint256 secondScore, uint256 secondTimestamp) = credoraScore.getScore(testWallet);

        assertEq(secondScore, 8000);
        assertGt(secondTimestamp, firstTimestamp);

        vm.stopPrank();
    }

    function test_WriteScore_Revert_NotOracle() public {
        vm.prank(nonOracle);
        vm.expectRevert(CredoraScore.NotOracle.selector);
        credoraScore.writeScore(testWallet, 5000);
    }

    function test_WriteScore_Revert_ScoreOutOfRange() public {
        vm.prank(oracle);
        vm.expectRevert(CredoraScore.ScoreOutOfRange.selector);
        credoraScore.writeScore(testWallet, 10001);
    }

    function test_WriteScore_AcceptsMaxScore() public {
        vm.prank(oracle);
        credoraScore.writeScore(testWallet, 10000);

        (uint256 score,) = credoraScore.getScore(testWallet);
        assertEq(score, 10000);
    }

    function test_WriteScore_AcceptsMinScore() public {
        vm.prank(oracle);
        credoraScore.writeScore(testWallet, 0);

        (uint256 score, uint256 timestamp) = credoraScore.getScore(testWallet);
        assertEq(score, 0);
        assertGt(timestamp, 0); // Timestamp should be set even for score 0
    }

    // getScore Tests

    function test_GetScore_Unscored() public view {
        (uint256 score, uint256 timestamp) = credoraScore.getScore(testWallet);
        assertEq(score, 0);
        assertEq(timestamp, 0);
    }

    function test_GetScore_ReturnsCorrectValues() public {
        uint256 expectedScore = 6543;

        vm.prank(oracle);
        credoraScore.writeScore(testWallet, expectedScore);

        (uint256 score, uint256 timestamp) = credoraScore.getScore(testWallet);
        assertEq(score, expectedScore);
        assertEq(timestamp, block.timestamp);
    }

    // isScoreFresh Tests

    function test_IsScoreFresh_UnscoredWallet() public view {
        bool isFresh = credoraScore.isScoreFresh(testWallet, 30 days);
        assertFalse(isFresh);
    }

    function test_IsScoreFresh_WithinMaxAge() public {
        vm.prank(oracle);
        credoraScore.writeScore(testWallet, 7000);

        // Check freshness immediately
        bool isFresh = credoraScore.isScoreFresh(testWallet, 30 days);
        assertTrue(isFresh);

        // Advance time but stay within maxAge
        vm.warp(block.timestamp + 15 days);
        isFresh = credoraScore.isScoreFresh(testWallet, 30 days);
        assertTrue(isFresh);
    }

    function test_IsScoreFresh_ExceedsMaxAge() public {
        vm.prank(oracle);
        credoraScore.writeScore(testWallet, 7000);

        // Advance time beyond maxAge
        vm.warp(block.timestamp + 31 days);

        bool isFresh = credoraScore.isScoreFresh(testWallet, 30 days);
        assertFalse(isFresh);
    }

    function test_IsScoreFresh_ExactlyAtMaxAge() public {
        vm.prank(oracle);
        credoraScore.writeScore(testWallet, 7000);

        // Advance time to exactly maxAge
        vm.warp(block.timestamp + 30 days);

        bool isFresh = credoraScore.isScoreFresh(testWallet, 30 days);
        assertTrue(isFresh); // Should be true at exactly maxAge
    }

    // setOracle Tests

    function test_SetOracle_Success() public {
        address newOracle = makeAddr("newOracle");

        vm.expectEmit(true, true, false, false);
        emit OracleUpdated(oracle, newOracle);

        credoraScore.setOracle(newOracle);

        assertEq(credoraScore.authorizedOracle(), newOracle);
    }

    function test_SetOracle_OnlyOwner() public {
        address newOracle = makeAddr("newOracle");

        vm.prank(nonOracle);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOracle));
        credoraScore.setOracle(newOracle);
    }

    function test_SetOracle_RevertsOnZeroAddress() public {
        vm.expectRevert(CredoraScore.ZeroAddress.selector);
        credoraScore.setOracle(address(0));
    }

    function test_SetOracle_EmitsEvent() public {
        address newOracle = makeAddr("newOracle");

        vm.recordLogs();
        credoraScore.setOracle(newOracle);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("OracleUpdated(address,address)"));
    }

    function test_SetOracle_NewOracleCanWrite() public {
        address newOracle = makeAddr("newOracle");

        // Set new oracle
        credoraScore.setOracle(newOracle);

        // New oracle can write
        vm.prank(newOracle);
        credoraScore.writeScore(testWallet, 5000);

        (uint256 score,) = credoraScore.getScore(testWallet);
        assertEq(score, 5000);
    }

    function test_SetOracle_OldOracleCannotWrite() public {
        address newOracle = makeAddr("newOracle");

        // Set new oracle
        credoraScore.setOracle(newOracle);

        // Old oracle cannot write
        vm.prank(oracle);
        vm.expectRevert(CredoraScore.NotOracle.selector);
        credoraScore.writeScore(testWallet, 5000);
    }

    // Fuzz Tests

    function testFuzz_WriteScore_ValidRange(uint256 score) public {
        vm.assume(score <= 10000);

        vm.prank(oracle);
        credoraScore.writeScore(testWallet, score);

        (uint256 storedScore,) = credoraScore.getScore(testWallet);
        assertEq(storedScore, score);
    }

    function testFuzz_WriteScore_InvalidRange(uint256 score) public {
        vm.assume(score > 10000);

        vm.prank(oracle);
        vm.expectRevert(CredoraScore.ScoreOutOfRange.selector);
        credoraScore.writeScore(testWallet, score);
    }

    function testFuzz_IsScoreFresh_MaxAge(uint256 maxAge, uint256 timeElapsed) public {
        maxAge = bound(maxAge, 1, 365 days);
        timeElapsed = bound(timeElapsed, 0, 730 days);

        vm.prank(oracle);
        credoraScore.writeScore(testWallet, 5000);

        vm.warp(block.timestamp + timeElapsed);

        bool isFresh = credoraScore.isScoreFresh(testWallet, maxAge);
        assertEq(isFresh, timeElapsed <= maxAge);
    }
}
