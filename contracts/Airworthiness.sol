// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface UAVPassportNFTInterface {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract Airworthiness {
    enum CertificationStatus { Pending, Certified, Rejected }

    struct Application {
        uint256 id;
        address uavTokenAddress;
        uint256 uavTokenId;
        string ipfsHashDocuments;
        CertificationStatus status;
    }

    uint256 public applicationCounter;
    mapping(uint256 => Application) public applications;
    address public regulatoryAuthority;

    event ApplicationSubmitted(uint256 indexed applicationId);
    event InspectionCompleted(uint256 indexed applicationId, string inspectionReportHash);
    event CertificateIssued(uint256 indexed applicationId, string airworthinessCertificateHash);

    constructor(address _regulatoryAuthority) {
    require(_regulatoryAuthority != address(0), "Invalid address");
        regulatoryAuthority = _regulatoryAuthority;
    }

    modifier onlyRegulatoryAuthority() {
        require(msg.sender == regulatoryAuthority, "Only regulatory authority allowed");
        _;
    }

    function submitApplication(address uavNFTAddress, uint256 uavTokenId, string memory ipfsHashDocuments) external {
         // Create an instance of the UAVPassportNFT contract
        UAVPassportNFTInterface uavPassportNFT = UAVPassportNFTInterface(uavNFTAddress);

        // Verify ownership
        require(uavPassportNFT.ownerOf(uavTokenId) == msg.sender, "Caller does not own the specified UAVPassportNFT");

        applicationCounter++;
        applications[applicationCounter] = Application(applicationCounter, uavNFTAddress, uavTokenId, ipfsHashDocuments, CertificationStatus.Pending);
        
        emit ApplicationSubmitted(applicationCounter);
    }

    function completeInspection(uint256 applicationId, string memory inspectionReportHash) external onlyRegulatoryAuthority {
        emit InspectionCompleted(applicationId, inspectionReportHash);
    }

function issueCertificate(uint256 applicationId, string memory airworthinessCertificateHash) external onlyRegulatoryAuthority {
    Application storage app = applications[applicationId];
    
    require(app.id != 0, "Application does not exist"); // Ensure the application exists
    require(app.status == CertificationStatus.Pending, "Application is not pending");

    app.status = CertificationStatus.Certified;
    emit CertificateIssued(applicationId, airworthinessCertificateHash);
}

    function isCertified(uint256 applicationId) external view returns (bool) {
        Application storage app = applications[applicationId];
        return app.id != 0 && app.status == CertificationStatus.Certified;
    }
}