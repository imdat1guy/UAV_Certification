// testUAVPassportAirworthiness.js

// Right click on the script name and hit "Run" to execute
(async () => {
    try {
        console.log('Starting UAVPassportNFT, Airworthiness, and CertificateNFT contract test...');

        // Constants (replace with actual values)
        const serialNumber = 'SN-123456'; // UAV serial number
        const typeCertificateContractAddress = '0x5A86858aA3b595FD6663c2296741eF4cd8BC4d01'; 
        const typeCertificateApplicationId = 1; // Replace with actual ID of Type Ceritifcate for this UAV
        const uavIpfsMetadataCID = 'QmUAVMetadata'; // UAV metadata CID

        const airworthinessDocsCID = 'QmAirworthinessDocs'; // Airworthiness documents CID
        const inspectionReportHash = 'QmInspectionReport'; // Inspection report hash
        const airworthinessCertificateURI = 'ipfs://QmAirworthinessCertificateMetadata'; // Certificate metadata URI

        // Import necessary modules
        const { ethers } = require('ethers');

        // Set up provider and signers
        const provider = new ethers.providers.Web3Provider(web3Provider); // web3Provider is injected by Remix
        const accounts = await provider.listAccounts();

        // Assign roles
        const regulatoryAuthority = provider.getSigner(0);
        const manufacturer = provider.getSigner(1);
        const notifiedBody = provider.getSigner(2);

        const regulatoryAuthorityAddress = await regulatoryAuthority.getAddress();
        const manufacturerAddress = await manufacturer.getAddress();
        const notifiedBodyAddress = await notifiedBody.getAddress();

        console.log('Regulatory Authority Address:', regulatoryAuthorityAddress);
        console.log('Manufacturer Address:', manufacturerAddress);
        console.log('Notified Body Address:', notifiedBodyAddress);

        // Deploy UAVPassportNFT contract
        console.log('\nDeploying UAVPassportNFT contract...');
        const uavPassportFactory = await ethers.getContractFactory('UAVPassportNFT', regulatoryAuthority);
        const uavPassportContract = await uavPassportFactory.deploy();
        await uavPassportContract.deployed();
        console.log('UAVPassportNFT contract deployed at:', uavPassportContract.address);

        // Grant roles in UAVPassportNFT contract
        console.log('\nGranting roles in UAVPassportNFT contract...');
        // Grant MANUFACTURER_ROLE to manufacturer
        const MANUFACTURER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes('MANUFACTURER_ROLE'));
        let tx = await uavPassportContract.connect(regulatoryAuthority).addManufacturer(manufacturerAddress);
        let receipt = await tx.wait();
        console.log('MANUFACTURER_ROLE granted to manufacturer.');

        // Grant AUTHORITY_ROLE to regulatory authority
        const AUTHORITY_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes('AUTHORITY_ROLE'));
        tx = await uavPassportContract.connect(regulatoryAuthority).addAuthority(regulatoryAuthorityAddress);
        receipt = await tx.wait();
        console.log('AUTHORITY_ROLE granted to regulatory authority.');

        // Deploy CertificateNFT contract
        console.log('\nDeploying CertificateNFT contract...');
        const certificateNFTFactory = await ethers.getContractFactory('CertificateNFT', regulatoryAuthority);
        const certificateNFTContract = await certificateNFTFactory.deploy();
        await certificateNFTContract.deployed();
        console.log('CertificateNFT contract deployed at:', certificateNFTContract.address);

        // Grant AUTHORITY_ROLE to the regulatory authority in CertificateNFT contract
        tx = await certificateNFTContract.connect(regulatoryAuthority).addAuthority(regulatoryAuthorityAddress);
        receipt = await tx.wait();
        console.log('AUTHORITY_ROLE granted to regulatory authority in CertificateNFT contract.');

        // Deploy Airworthiness contract
        console.log('\nDeploying Airworthiness contract...');
        const airworthinessFactory = await ethers.getContractFactory('Airworthiness', regulatoryAuthority);
        const airworthinessContract = await airworthinessFactory.deploy(regulatoryAuthorityAddress);
        await airworthinessContract.deployed();
        console.log('Airworthiness contract deployed at:', airworthinessContract.address);

        // 1. Manufacturer mints UAV NFT
        console.log('\nManufacturer minting UAV NFT...');
        tx = await uavPassportContract.connect(manufacturer).mintUAV(
            serialNumber,
            typeCertificateContractAddress,
            typeCertificateApplicationId,
            uavIpfsMetadataCID
        );
        receipt = await tx.wait();
        let event = receipt.events.find(event => event.event === 'UAVMinted');
        logTransactionDetails(tx, receipt, event);
        const uavTokenId = event.args.tokenId.toNumber();
        console.log('UAV NFT minted with Token ID:', uavTokenId);

        // 2. Manufacturer submits airworthiness application
        console.log('\nManufacturer submitting airworthiness application...');
        tx = await airworthinessContract.connect(manufacturer).submitApplication(
            uavPassportContract.address,
            uavTokenId,
            airworthinessDocsCID
        );
        receipt = await tx.wait();
        event = receipt.events.find(event => event.event === 'ApplicationSubmitted');
        logTransactionDetails(tx, receipt, event);
        const applicationId = receipt.events.find(event => event.event === 'ApplicationSubmitted').args.applicationId.toNumber();
        console.log('Airworthiness application submitted with ID:', applicationId);

        // 3. Regulatory authority completes inspection
        console.log('\nRegulatory authority completing inspection...');
        tx = await airworthinessContract.connect(regulatoryAuthority).completeInspection(applicationId, inspectionReportHash);
        receipt = await tx.wait();
        event = receipt.events.find(event => event.event === 'InspectionCompleted');
        logTransactionDetails(tx, receipt, event);
        console.log('Inspection completed.');

        // 4. Regulatory authority issues certificate
        console.log('\nRegulatory authority issuing certificate...');
        tx = await airworthinessContract.connect(regulatoryAuthority).issueCertificate(applicationId, airworthinessCertificateURI);
        receipt = await tx.wait();
        event = receipt.events.find(event => event.event === 'CertificateIssued');
        logTransactionDetails(tx, receipt, event);
        console.log('Certificate issued.');

        // 5. Regulatory authority mints Certificate NFT
        console.log('\nRegulatory authority minting Certificate NFT...');
        tx = await certificateNFTContract.connect(regulatoryAuthority).mintCertificate(
            airworthinessCertificateURI,
            0, // CertificateTypes.CertificateType.Airworthiness
            regulatoryAuthorityAddress,
            airworthinessContract.address,
            applicationId
        );
        receipt = await tx.wait();
        event = receipt.events.find(event => event.event === 'CertificateMinted');
        logTransactionDetails(tx, receipt, event);
        const certificateTokenId = event.args.tokenId.toNumber();
        console.log('Certificate NFT minted with Token ID:', certificateTokenId);

        // 6. Regulatory authority links Certificate NFT to UAV NFT
        
        // 6.1 Regulatory authority approves UAVPassportNFT contract to transfer Certificate NFT
        console.log('\nRegulatory authority approving UAVPassportNFT contract to transfer Certificate NFT...');
        tx = await certificateNFTContract.connect(regulatoryAuthority).approve(uavPassportContract.address, certificateTokenId);
        receipt = await tx.wait();
        console.log('Approval granted.');

        // 6.2 Now proceed to link the certificate
        console.log('\nRegulatory authority linking Certificate NFT to UAV NFT...');
        tx = await uavPassportContract.connect(regulatoryAuthority).linkCertificate(
            uavTokenId,
            certificateNFTContract.address,
            certificateTokenId
        );
        receipt = await tx.wait();
        event = receipt.events.find(event => event.event === 'CertificateLinked');
        logTransactionDetails(tx, receipt, event);
        console.log('Certificate linked to UAV NFT.');

        // 7. Retrieve UAV NFT details
        console.log('\nRetrieving UAV NFT details...');
        const uavData = await uavPassportContract.getUAVData(uavTokenId);
        console.log('UAV Data:', uavData);
        const linkedCertificates = await uavPassportContract.getLinkedCertificates(uavTokenId);
        console.log('Linked Certificates:', linkedCertificates);

        // Helper function to log transaction details
        function logTransactionDetails(tx, receipt, event) {  
            console.log('-----------------------------------------\n');  
            console.log('Transaction Details:');
            console.log(`  From:                 ${tx.from}`);
            console.log(`  To:                   ${tx.to}`);
            console.log(`  Value:                ${tx.value.toString()} wei`);
            console.log(`  Gas Limit:            ${tx.gasLimit.toString()}`);
            console.log(`  Gas Used:             ${receipt.gasUsed.toString()}`);
            console.log(`  Data:                 ${tx.data}`);
            console.log(`  Transaction Hash:     ${tx.hash}`);
            console.log(`  Block Number:         ${receipt.blockNumber}`);
            console.log(`  Status:               ${receipt.status === 1 ? 'Success' : 'Failure'}`);

            if (event) {
                console.log('  Topics:');
                // Loop through topics and print each on a new line with indentation
                event.topics.forEach((topic, index) => {
                    console.log(`    ${index + 1}: ${topic}`);
                });

                console.log(`  Event:         ${event.event}`);
                console.log('  Args:');
                for (const [key, value] of Object.entries(event.args)) {
                    // Format BigNumber values as strings
                    const formattedValue = value._isBigNumber ? value.toString() : value;
                    console.log(`    ${key}: ${formattedValue}`);
                }
            }
            console.log('-----------------------------------------\n');
        }

        console.log('\nTest completed successfully.');

    } catch (error) {
        if (error instanceof Error) {
            console.error('Error during testing:', error.message);
            console.error(error.stack);
        } else {
            console.error('Error during testing:', error);
        }
    }
})();
