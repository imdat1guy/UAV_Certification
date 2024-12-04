// testTypeCertificate.js

// Right click on the script name and hit "Run" to execute
(async () => {
    try {
        console.log('Starting TypeCertificate contract test...');

        // Import necessary modules
        const { ethers } = require('ethers');
        const { expect } = require('chai');

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

        // Get the contract factory directly
        const contractName = 'TypeCertificate'; // Update if your contract name is different
        const contractFactory = await ethers.getContractFactory(contractName, regulatoryAuthority);

        // Deploy the contract
        console.log('\nDeploying the contract...');
        const contract = await contractFactory.deploy();
        await contract.deployed();
        console.log('Contract deployed at:', contract.address);

        // Testing workflow

        // Constants (replace with actual values)
        const ipfsDirectoryCID = 'QmManufacturerDocuments'; // Manufacturer's documents CID
        const droneSpecDocumentHash = ethers.utils.formatBytes32String('DroneSpecHash');
        const certificationSpecificationsCID = 'QmCertificationSpecs'; // Regulatory authority's certification specifications CID
        const internalReportCID = 'QmInternalReport'; // Manufacturer's internal report CID
        const notifiedBodyReportCID = 'QmInspectionReport'; // Notified body's inspection report CID
        const typeCertificateCID = 'QmTypeCertificate'; // Final type certificate CID

        // 1. Manufacturer submits application
        console.log('\nManufacturer submitting application...');
        let tx = await contract.connect(manufacturer).submitApplication(ipfsDirectoryCID, droneSpecDocumentHash);
        let receipt = await tx.wait();
        let event = receipt.events.find(event => event.event === 'ApplicationSubmitted');
        logTransactionDetails(tx, receipt, event);
        let applicationId = event.args.applicationId.toNumber();
        console.log('Application submitted with ID:', applicationId);

        // 2. Regulatory authority approves documents
        console.log('\nRegulatory authority approving documents...');
        tx = await contract.connect(regulatoryAuthority).approveDocuments(applicationId, certificationSpecificationsCID);
        receipt = await tx.wait();
        event = receipt.events.find(event => event.event === 'DocumentsApproved');
        logTransactionDetails(tx, receipt, event);
        console.log('Documents approved.');

        // 3. Manufacturer requests type examination
        console.log('\nManufacturer requesting type examination...');
        tx = await contract.connect(manufacturer).requestTypeExamination(applicationId, internalReportCID);
        receipt = await tx.wait();
        event = receipt.events.find(event => event.event === 'ExaminationRequested');
        logTransactionDetails(tx, receipt, event);
        console.log('Type examination requested.');

        // 4. Regulatory authority authorizes notified body
        console.log('\nRegulatory authority authorizing notified body...');
        tx = await contract.connect(regulatoryAuthority).authorizeNotifiedBody(notifiedBodyAddress);
        receipt = await tx.wait();
        event = receipt.events.find(event => event.event === 'NotifiedBodyAuthorized');
        logTransactionDetails(tx, receipt, event);
        console.log('Notified body authorized.');

        // 5. Notified body completes inspection
        console.log('\nNotified body completing inspection...');
        tx = await contract.connect(notifiedBody).completeInspection(applicationId, notifiedBodyReportCID);
        receipt = await tx.wait();
        event = receipt.events.find(event => event.event === 'InspectionCompleted');
        logTransactionDetails(tx, receipt, event);
        console.log('Inspection completed.');

        // 6. Regulatory authority issues certificate
        console.log('\nRegulatory authority issuing certificate...');
        tx = await contract.connect(regulatoryAuthority).issueCertificate(applicationId, typeCertificateCID);
        receipt = await tx.wait();
        event = receipt.events.find(event => event.event === 'CertificateIssued');
        logTransactionDetails(tx, receipt, event);
        console.log('Certificate issued.');

        // 7. Retrieve application details
        console.log('\nRetrieving application details...');
        const application = await contract.getApplication(applicationId);
        console.log('Application Details:');
        console.log(`ID: ${application.id.toString()}`);
        console.log(`Manufacturer: ${application.manufacturer}`);
        console.log(`Status: ${certificateStatusToString(application.status)}`);
        console.log(`Assigned Notified Body: ${application.assignedNotifiedBody}`);
        console.log(`Notified Body Report CID: ${application.notifiedBodyReportCID}`);

        // Helper function to map status enum
        function certificateStatusToString(status) {
            const statuses = ['Pending', 'DocumentsApproved', 'UnderReview', 'Certified', 'Rejected'];
            return statuses[status];
        }

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
        console.error('Error during testing:', error);
    }
})();
