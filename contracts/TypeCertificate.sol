// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TypeCertificate {
    enum CertificateStatus { Pending, DocumentsApproved, UnderReview, Certified, Rejected }

    struct Application {
        uint256 id;
        address manufacturer;
        string ipfsDirectoryCID; // CID of the IPFS directory containing all non-sensitive documents
        bytes32 droneSpecDocumentHash; // Hash of sensitive drone specification
        CertificateStatus status;
        address assignedNotifiedBody; // Notified body assigned to the application
        string notifiedBodyReportCID;
    }

    //variables
    uint256 public applicationCounter;
    mapping(uint256 => Application) public applications;
    address public regulatoryAuthority;
    mapping(address => bool) public notifiedBodies;

    //events
    event NotifiedBodyAuthorized(address notifiedBody);
    event NotifiedBodyRevoked(address notifiedBody);

    event ApplicationSubmitted(uint256 indexed applicationId, address indexed manufacturer); 
    event DocumentsUpdated(uint256 indexed applicationId);
    event DocumentsApproved(uint256 indexed applicationId, string csCID);

    event ExaminationRequested(uint256 indexed applicationId, string internalReportCID);
    event InspectionCompleted(uint256 indexed applicationId, address notifiedBody);

    event ApplicationRejected(uint256 indexed applicationId);
    event CertificateIssued(uint256 indexed applicationId, string ipfsHashCertificate); 

    constructor() {
        regulatoryAuthority = msg.sender; //deployed by the regulatory authority (FAA, EASA, etc.)
    }

    modifier onlyRegulatoryAuthority() {
        require(msg.sender == regulatoryAuthority, "Only regulatory authority allowed");
        _;
    }

    modifier onlyManufacturer(uint256 applicationId) {
        require(msg.sender == applications[applicationId].manufacturer, "Not authorized");
        _;
    }

    modifier onlyNotifiedBody() {
        require(notifiedBodies[msg.sender], "Not an authorized notified body");
        _;
    }

    // Manufacturer submits application
    function submitApplication(string memory ipfsDirectoryCID, bytes32 droneSpecDocumentHash) external {
        applicationCounter++;
        applications[applicationCounter] = Application({
            id: applicationCounter,
            manufacturer: msg.sender,
            ipfsDirectoryCID: ipfsDirectoryCID,
            droneSpecDocumentHash: droneSpecDocumentHash,
            status: CertificateStatus.Pending,
            assignedNotifiedBody: address(0),
            notifiedBodyReportCID: ""
        });

        emit ApplicationSubmitted(
            applicationCounter,
            msg.sender
        );
    }

    // Manufacturer updates documents
    function updateDocuments( uint256 applicationId, string memory updatedIpfsDirectoryCID, bytes32 updatedDroneSpecDocumentHash) external onlyManufacturer(applicationId) {
        require(
            applications[applicationId].status == CertificateStatus.Pending,
            "Cannot update documents at this stage"
        );

        applications[applicationId].ipfsDirectoryCID  = updatedIpfsDirectoryCID;
        applications[applicationId].droneSpecDocumentHash = updatedDroneSpecDocumentHash;

         emit DocumentsUpdated(applicationId);
    }

    // Regulatory authority approves initial documents and issues Certification Specifications
    function approveDocuments(uint256 applicationId, string memory certificationSpecificationsCID) external onlyRegulatoryAuthority {
        Application storage app = applications[applicationId];
        require(app.status == CertificateStatus.Pending, "Application not pending");
        app.status = CertificateStatus.DocumentsApproved;

        emit DocumentsApproved(applicationId, certificationSpecificationsCID);
    }

    //Authorize a notified body
    function authorizeNotifiedBody(address notifiedBody) external onlyRegulatoryAuthority {
        notifiedBodies[notifiedBody] = true;
        emit NotifiedBodyAuthorized(notifiedBody);
    }

    // Regulatory authority revokes a notified body
    function revokeNotifiedBody(address notifiedBody) external onlyRegulatoryAuthority {
        notifiedBodies[notifiedBody] = false;
        emit NotifiedBodyRevoked(notifiedBody);
    }

    // Manufacturer requests type examination
    function requestTypeExamination(uint256 applicationId, string memory internalReportCID) external onlyManufacturer(applicationId){
        Application storage app = applications[applicationId];
        require(app.status == CertificateStatus.DocumentsApproved, "Initial documents not approved");
        app.status = CertificateStatus.UnderReview;

        emit ExaminationRequested(applicationId, internalReportCID);
    }

    // Notified body completes inspection
    function completeInspection(uint256 applicationId, string memory notifiedBodyReportCID) external onlyNotifiedBody{
        Application storage app = applications[applicationId];
        require(app.status == CertificateStatus.UnderReview, "Application not under review");
        require(app.assignedNotifiedBody == address(0) || app.assignedNotifiedBody == msg.sender, "Not assigned to this application");

        app.assignedNotifiedBody = msg.sender;
        app.notifiedBodyReportCID = notifiedBodyReportCID;

        emit InspectionCompleted(applicationId, msg.sender);
    }

    // Regulatory authority issues certificate
    function issueCertificate(uint256 applicationId, string memory typeCertificateCID) external onlyRegulatoryAuthority{
        Application storage app = applications[applicationId];
        require(app.status == CertificateStatus.UnderReview, "Application not under review");
        require(bytes(app.notifiedBodyReportCID).length > 0, "Inspection not completed");

        app.status = CertificateStatus.Certified;

        // Instead of storing typeCertificateCID, we emit it in the event
        emit CertificateIssued(applicationId, typeCertificateCID);
    }

    // Regulatory authority rejects application
    function rejectApplication(uint256 applicationId) external onlyRegulatoryAuthority{
        Application storage app = applications[applicationId];
        require(
            app.status == CertificateStatus.Pending ||
            app.status == CertificateStatus.UnderReview,
            "Cannot reject at this stage"
        );

        app.status = CertificateStatus.Rejected;
        emit ApplicationRejected(applicationId);
    }

    function getApplication(uint256 applicationId) external view returns (Application memory){
        return applications[applicationId];
    }

}