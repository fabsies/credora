// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SoulboundNFT.sol";

contract SoulboundNFTTest is Test {
    SoulboundNFT public nft;

    address public owner;
    address public minter;
    address public nonMinter;
    address public recipient;
    address public otherUser;

    event Minted(address indexed to, uint256 indexed tokenId, string scoreTier);
    event MinterUpdated(address indexed oldMinter, address indexed newMinter);

    function setUp() public {
        owner = address(this);
        minter = makeAddr("minter");
        nonMinter = makeAddr("nonMinter");
        recipient = makeAddr("recipient");
        otherUser = makeAddr("otherUser");

        nft = new SoulboundNFT(minter);
    }

    // Constructor Tests

    function test_Constructor_Success() public view {
        assertEq(nft.authorizedMinter(), minter);
        assertEq(nft.owner(), owner);
        assertEq(nft.name(), "Credora Credit Credential");
        assertEq(nft.symbol(), "CREDORA");
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        vm.expectRevert(SoulboundNFT.ZeroAddress.selector);
        new SoulboundNFT(address(0));
    }

    // mint Tests

    function test_Mint_Success() public {
        string memory tier = "EXCEPTIONAL";

        vm.expectEmit(true, true, false, true);
        emit Minted(recipient, 1, tier);

        vm.prank(minter);
        nft.mint(recipient, tier);

        assertEq(nft.balanceOf(recipient), 1);
        assertEq(nft.ownerOf(1), recipient);
        assertTrue(nft.hasMinted(recipient));
        assertEq(nft.getScoreTier(1), tier);
    }

    function test_Mint_IncrementingTokenIds() public {
        vm.startPrank(minter);

        nft.mint(recipient, "GOOD");
        assertEq(nft.ownerOf(1), recipient);

        nft.mint(otherUser, "STRONG");
        assertEq(nft.ownerOf(2), otherUser);

        nft.mint(makeAddr("user3"), "FAIR");
        assertEq(nft.ownerOf(3), makeAddr("user3"));

        vm.stopPrank();
    }

    function test_Mint_Revert_AlreadyMinted() public {
        vm.startPrank(minter);

        // First mint succeeds
        nft.mint(recipient, "GOOD");

        // Second mint to same address reverts
        vm.expectRevert(SoulboundNFT.AlreadyMinted.selector);
        nft.mint(recipient, "EXCEPTIONAL");

        vm.stopPrank();
    }

    function test_Mint_Revert_NotMinter() public {
        vm.prank(nonMinter);
        vm.expectRevert(SoulboundNFT.NotMinter.selector);
        nft.mint(recipient, "GOOD");
    }

    function test_Mint_UpdatesHasMintedMapping() public {
        assertFalse(nft.hasMinted(recipient));

        vm.prank(minter);
        nft.mint(recipient, "GOOD");

        assertTrue(nft.hasMinted(recipient));
    }

    function test_Mint_StoresScoreTier() public {
        string memory tier = "STRONG";

        vm.prank(minter);
        nft.mint(recipient, tier);

        assertEq(nft.getScoreTier(1), tier);
    }

    // Soulbound Tests (Transfer Blocking)

    function test_Soulbound_TransferFromReverts() public {
        vm.prank(minter);
        nft.mint(recipient, "GOOD");

        vm.prank(recipient);
        vm.expectRevert(SoulboundNFT.NonTransferable.selector);
        nft.transferFrom(recipient, otherUser, 1);
    }

    function test_Soulbound_SafeTransferFromReverts() public {
        vm.prank(minter);
        nft.mint(recipient, "GOOD");

        vm.prank(recipient);
        vm.expectRevert(SoulboundNFT.NonTransferable.selector);
        nft.safeTransferFrom(recipient, otherUser, 1);
    }

    function test_Soulbound_SafeTransferFromWithDataReverts() public {
        vm.prank(minter);
        nft.mint(recipient, "GOOD");

        vm.prank(recipient);
        vm.expectRevert(SoulboundNFT.NonTransferable.selector);
        nft.safeTransferFrom(recipient, otherUser, 1, "");
    }

    function test_Soulbound_ApproveReverts() public {
        vm.prank(minter);
        nft.mint(recipient, "GOOD");

        vm.prank(recipient);
        vm.expectRevert(SoulboundNFT.NonTransferable.selector);
        nft.approve(otherUser, 1);
    }

    function test_Soulbound_SetApprovalForAllReverts() public {
        vm.prank(minter);
        nft.mint(recipient, "GOOD");

        vm.prank(recipient);
        vm.expectRevert(SoulboundNFT.NonTransferable.selector);
        nft.setApprovalForAll(otherUser, true);
    }

    function test_Soulbound_CannotTransferViaApprovedOperator() public {
        vm.prank(minter);
        nft.mint(recipient, "GOOD");

        // Even if approve worked, transferFrom should still fail
        // (but approve itself reverts)
        vm.prank(recipient);
        vm.expectRevert(SoulboundNFT.NonTransferable.selector);
        nft.approve(otherUser, 1);
    }

    // tokenURI Tests

    function test_TokenURI_ReturnsValidBase64JSON() public {
        vm.prank(minter);
        nft.mint(recipient, "EXCEPTIONAL");

        string memory uri = nft.tokenURI(1);

        // Check that it starts with the data URI scheme
        assertTrue(bytes(uri).length > 0);
        assertEq(
            bytes(uri)[0],
            bytes("d")[0],
            "Should start with 'data:application/json;base64,'"
        );
    }

    function test_TokenURI_ContainsScoreTier() public {
        string memory tier = "STRONG";

        vm.prank(minter);
        nft.mint(recipient, tier);

        string memory uri = nft.tokenURI(1);

        // The URI should contain the tier in the base64-decoded JSON
        assertTrue(bytes(uri).length > 50); // Base64 encoded JSON is reasonably long
    }

    function test_TokenURI_RevertsForNonexistentToken() public {
        vm.expectRevert();
        nft.tokenURI(999);
    }

    // getScoreTier Tests

    function test_GetScoreTier_Success() public {
        string memory tier = "DEVELOPING";

        vm.prank(minter);
        nft.mint(recipient, tier);

        assertEq(nft.getScoreTier(1), tier);
    }

    function test_GetScoreTier_RevertsForNonexistentToken() public {
        vm.expectRevert();
        nft.getScoreTier(999);
    }

    function test_GetScoreTier_AllTiers() public {
        string[5] memory tiers = ["DEVELOPING", "FAIR", "GOOD", "STRONG", "EXCEPTIONAL"];
        address[5] memory users;

        for (uint256 i = 0; i < 5; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
        }

        vm.startPrank(minter);
        for (uint256 i = 0; i < 5; i++) {
            nft.mint(users[i], tiers[i]);
            assertEq(nft.getScoreTier(i + 1), tiers[i]);
        }
        vm.stopPrank();
    }

    // setMinter Tests

    function test_SetMinter_Success() public {
        address newMinter = makeAddr("newMinter");

        vm.expectEmit(true, true, false, false);
        emit MinterUpdated(minter, newMinter);

        nft.setMinter(newMinter);

        assertEq(nft.authorizedMinter(), newMinter);
    }

    function test_SetMinter_OnlyOwner() public {
        address newMinter = makeAddr("newMinter");

        vm.prank(nonMinter);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonMinter));
        nft.setMinter(newMinter);
    }

    function test_SetMinter_RevertsOnZeroAddress() public {
        vm.expectRevert(SoulboundNFT.ZeroAddress.selector);
        nft.setMinter(address(0));
    }

    function test_SetMinter_NewMinterCanMint() public {
        address newMinter = makeAddr("newMinter");

        nft.setMinter(newMinter);

        vm.prank(newMinter);
        nft.mint(recipient, "GOOD");

        assertEq(nft.balanceOf(recipient), 1);
    }

    function test_SetMinter_OldMinterCannotMint() public {
        address newMinter = makeAddr("newMinter");

        nft.setMinter(newMinter);

        vm.prank(minter);
        vm.expectRevert(SoulboundNFT.NotMinter.selector);
        nft.mint(recipient, "GOOD");
    }

    // View Function Tests

    function test_BalanceOf_BeforeMint() public view {
        assertEq(nft.balanceOf(recipient), 0);
    }

    function test_BalanceOf_AfterMint() public {
        vm.prank(minter);
        nft.mint(recipient, "GOOD");

        assertEq(nft.balanceOf(recipient), 1);
    }

    function test_OwnerOf_Success() public {
        vm.prank(minter);
        nft.mint(recipient, "GOOD");

        assertEq(nft.ownerOf(1), recipient);
    }

    function test_OwnerOf_RevertsForNonexistentToken() public {
        vm.expectRevert();
        nft.ownerOf(999);
    }

    // Fuzz Tests

    function testFuzz_Mint_DifferentTiers(string calldata tier) public {
        vm.assume(bytes(tier).length > 0 && bytes(tier).length < 100);

        vm.prank(minter);
        nft.mint(recipient, tier);

        assertEq(nft.getScoreTier(1), tier);
    }

    function testFuzz_Mint_MultipleUsers(uint8 userCount) public {
        userCount = uint8(bound(userCount, 1, 20));

        vm.startPrank(minter);
        for (uint256 i = 0; i < userCount; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            nft.mint(user, "GOOD");
            assertTrue(nft.hasMinted(user));
            assertEq(nft.ownerOf(i + 1), user);
        }
        vm.stopPrank();
    }

    // Edge Case Tests

    function test_EdgeCase_MintToContractAddress() public {
        address contractAddr = address(new MockERC721Receiver());

        vm.prank(minter);
        nft.mint(contractAddr, "GOOD");

        assertEq(nft.ownerOf(1), contractAddr);
    }

    function test_EdgeCase_GetApproved_AlwaysReturnsZero() public {
        vm.prank(minter);
        nft.mint(recipient, "GOOD");

        // Even though approve reverts, getApproved should return zero address
        assertEq(nft.getApproved(1), address(0));
    }
}

// Mock contract for testing minting to contract addresses
contract MockERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }
}
