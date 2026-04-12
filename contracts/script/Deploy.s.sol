// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/CredoraScore.sol";
import "../src/SoulboundNFT.sol";
import "../src/OracleBridge.sol";

/**
 * @title Deploy
 * @notice Deployment script for Credora protocol contracts
 * @dev Deploys CredoraScore, SoulboundNFT, and OracleBridge in correct dependency order
 */
contract Deploy is Script {
    // Addresses that will be set from environment or constructor args
    address public oracleSigner;
    address public deployer;

    function run() external {
        // Read deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        // Read oracle signer address from environment
        // This should be the address corresponding to the backend's ORACLE_PRIVATE_KEY
        oracleSigner = vm.envAddress("ORACLE_ADDRESS");

        console.log("=================================================");
        console.log("CREDORA DEPLOYMENT SCRIPT");
        console.log("=================================================");
        console.log("Deployer address:", deployer);
        console.log("Oracle signer address:", oracleSigner);
        console.log("Chain ID:", block.chainid);
        console.log("=================================================");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy CredoraScore
        console.log("Deploying CredoraScore...");

        // Initially set deployer as authorized oracle (will be changed to OracleBridge)
        CredoraScore credoraScore = new CredoraScore(deployer);

        console.log("CredoraScore deployed at:", address(credoraScore));
        console.log(
            "Initial authorized oracle:",
            credoraScore.authorizedOracle()
        );
        console.log("");

        // 2. Deploy SoulboundNFT
        console.log("Deploying SoulboundNFT...");

        // Initially set deployer as authorized minter (will be changed to OracleBridge)
        SoulboundNFT soulboundNFT = new SoulboundNFT(deployer);

        console.log("SoulboundNFT deployed at:", address(soulboundNFT));
        console.log(
            "Initial authorized minter:",
            soulboundNFT.authorizedMinter()
        );
        console.log("");

        // 3. Deploy OracleBridge
        console.log("Deploying OracleBridge...");

        OracleBridge oracleBridge = new OracleBridge(
            oracleSigner,
            address(credoraScore),
            address(soulboundNFT)
        );

        console.log("OracleBridge deployed at:", address(oracleBridge));
        console.log("Oracle signer:", oracleBridge.oracleSigner());
        console.log(
            "CredoraScore reference:",
            address(oracleBridge.credoraScore())
        );
        console.log(
            "SoulboundNFT reference:",
            address(oracleBridge.soulboundNFT())
        );
        console.log("");

        // 4. Configure Permissions
        console.log("Configuring permissions...");

        // Set OracleBridge as the authorized oracle for CredoraScore
        credoraScore.setOracle(address(oracleBridge));
        console.log("Set OracleBridge as authorized oracle in CredoraScore");

        // Set OracleBridge as the authorized minter for SoulboundNFT
        soulboundNFT.setMinter(address(oracleBridge));
        console.log("Set OracleBridge as authorized minter in SoulboundNFT");
        console.log("");

        vm.stopBroadcast();

        // 5. Verification Summary
        console.log("=================================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("=================================================");
        console.log("CredoraScore:", address(credoraScore));
        console.log("SoulboundNFT:", address(soulboundNFT));
        console.log("OracleBridge:", address(oracleBridge));
        console.log("=================================================");
        console.log("");

        console.log("Add these to your .env.local (frontend):");
        console.log(
            "NEXT_PUBLIC_CREDORA_SCORE_ADDRESS=%s",
            address(credoraScore)
        );
        console.log(
            "NEXT_PUBLIC_SOULBOUND_NFT_ADDRESS=%s",
            address(soulboundNFT)
        );
        console.log(
            "NEXT_PUBLIC_ORACLE_BRIDGE_ADDRESS=%s",
            address(oracleBridge)
        );
        console.log("");

        console.log("Verify contracts on Basescan:");
        if (block.chainid == 84532) {
            console.log("Base Sepolia Explorer: https://sepolia.basescan.org");
        } else if (block.chainid == 8453) {
            console.log("Base Mainnet Explorer: https://basescan.org");
        }
        console.log("");

        // 6. Post-Deployment Checks
        console.log("Running post-deployment checks...");

        // Verify CredoraScore configuration
        require(
            credoraScore.authorizedOracle() == address(oracleBridge),
            "CredoraScore: Oracle not set correctly"
        );
        require(
            credoraScore.owner() == deployer,
            "CredoraScore: Owner not set correctly"
        );

        // Verify SoulboundNFT configuration
        require(
            soulboundNFT.authorizedMinter() == address(oracleBridge),
            "SoulboundNFT: Minter not set correctly"
        );
        require(
            soulboundNFT.owner() == deployer,
            "SoulboundNFT: Owner not set correctly"
        );

        // Verify OracleBridge configuration
        require(
            oracleBridge.oracleSigner() == oracleSigner,
            "OracleBridge: Signer not set correctly"
        );
        require(
            oracleBridge.owner() == deployer,
            "OracleBridge: Owner not set correctly"
        );
        require(
            address(oracleBridge.credoraScore()) == address(credoraScore),
            "OracleBridge: CredoraScore reference incorrect"
        );
        require(
            address(oracleBridge.soulboundNFT()) == address(soulboundNFT),
            "OracleBridge: SoulboundNFT reference incorrect"
        );

        console.log("All post-deployment checks passed!");
        console.log("");

        console.log("=================================================");
        console.log("NEXT STEPS:");
        console.log("=================================================");
        console.log(
            "1. Update frontend/.env.local with contract addresses above"
        );
        console.log("2. Verify contracts on Basescan using:");
        console.log(
            "   forge verify-contract <ADDRESS> <CONTRACT> --chain-id %s",
            block.chainid
        );
        console.log("3. Test the deployment with cast calls:");
        console.log(
            "   cast call <CREDORA_SCORE_ADDR> 'authorizedOracle()' --rpc-url <RPC>"
        );
        console.log(
            "4. For MAINNET: Transfer ownership to multisig before launch!"
        );
        console.log("=================================================");
    }
}
