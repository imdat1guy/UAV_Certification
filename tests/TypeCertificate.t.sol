// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "contracts/TypeCertificate.sol";

contract TypeCertificateTest is Test {
    TypeCertificate typeCertificate;

    address regulatoryAuthority = address(1);
    address manufacturer = address(2);
    address notifiedBody = address(3);
    address unauthorizedUser = address(4);

    string initialIpfsCID = "ipfs://initial-docs";
    bytes32 initialDroneSpecHash = keccak256("drone-spec");
    uint256 testApplicationId = 1;

    function setUp() public {
        vm.prank(regulatoryAuthority);
        typeCertificate = new TypeCertificate();

        vm.prank(regulatoryAuthority);
        typeCertificate.authorizeNotifiedBody(notifiedBody);
    }

    function test_ShouldAllowManufacturerToSubmitApplication() public {
        vm.prank(manufacturer);
        typeCertificate.submitApplication(initialIpfsCID, initialDroneSpecHash);

        TypeCertificate.Application memory app = typeCertificate.getApplication(testApplicationId);
        
        assertEq(app.id, testApplicationId);
        assertEq(app.manufacturer, manufacturer);
        assertEq(uint256(app.status), uint256(TypeCertificate.CertificateStatus.Pending));
    }

    function test_ShouldAllowManufacturerToUpdateDocuments() public {
        vm.prank(manufacturer);
        typeCertificate.submitApplication(initialIpfsCID, initialDroneSpecHash);

        string memory updatedIpfsCID = "ipfs://updated-docs";
        bytes32 updatedDroneSpecHash = keccak256("updated-spec");

        vm.prank(manufacturer);
        typeCertificate.updateDocuments(testApplicationId, updatedIpfsCID, updatedDroneSpecHash);

        TypeCertificate.Application memory app = typeCertificate.getApplication(testApplicationId);

        assertEq(keccak256(bytes(app.ipfsDirectoryCID)), keccak256(bytes(updatedIpfsCID)));
        assertEq(app.droneSpecDocumentHash, updatedDroneSpecHash);
    }

    function test_ShouldFailIfNonOwnerTriesToUpdateDocuments() public {
        vm.prank(manufacturer);
        typeCertificate.submitApplication(initialIpfsCID, initialDroneSpecHash);

        string memory updatedIpfsCID = "ipfs://updated-docs";
        bytes32 updatedDroneSpecHash = keccak256("updated-spec");

        vm.prank(unauthorizedUser);
        vm.expectRevert("Not authorized");
        typeCertificate.updateDocuments(testApplicationId, updatedIpfsCID, updatedDroneSpecHash);
    }

    function test_ShouldAllowRegulatoryAuthorityToApproveDocuments() public {
        vm.prank(manufacturer);
        typeCertificate.submitApplication(initialIpfsCID, initialDroneSpecHash);

        string memory certificationSpecCID = "ipfs://certification-specs";

        vm.prank(regulatoryAuthority);
        typeCertificate.approveDocuments(testApplicationId, certificationSpecCID);

        TypeCertificate.Application memory app = typeCertificate.getApplication(testApplicationId);
        assertEq(uint256(app.status), uint256(TypeCertificate.CertificateStatus.DocumentsApproved));
    }

    function test_ShouldAllowNotifiedBodyToCompleteInspection() public {
        vm.prank(manufacturer);
        typeCertificate.submitApplication(initialIpfsCID, initialDroneSpecHash);

        vm.prank(regulatoryAuthority);
        typeCertificate.approveDocuments(testApplicationId, "ipfs://certification-specs");

        vm.prank(manufacturer);
        typeCertificate.requestTypeExamination(testApplicationId, "ipfs://internal-report");

        string memory inspectionReportCID = "ipfs://inspection-report";

        vm.prank(notifiedBody);
        typeCertificate.completeInspection(testApplicationId, inspectionReportCID);

        TypeCertificate.Application memory app = typeCertificate.getApplication(testApplicationId);
        assertEq(app.assignedNotifiedBody, notifiedBody);
        assertEq(keccak256(bytes(app.notifiedBodyReportCID)), keccak256(bytes(inspectionReportCID)));
    }

    function test_ShouldAllowRegulatoryAuthorityToIssueCertificate() public {
        vm.prank(manufacturer);
        typeCertificate.submitApplication(initialIpfsCID, initialDroneSpecHash);

        vm.prank(regulatoryAuthority);
        typeCertificate.approveDocuments(testApplicationId, "ipfs://certification-specs");

        vm.prank(manufacturer);
        typeCertificate.requestTypeExamination(testApplicationId, "ipfs://internal-report");

        vm.prank(notifiedBody);
        typeCertificate.completeInspection(testApplicationId, "ipfs://inspection-report");

        string memory certificateCID = "ipfs://final-certificate";

        vm.prank(regulatoryAuthority);
        typeCertificate.issueCertificate(testApplicationId, certificateCID);

        TypeCertificate.Application memory app = typeCertificate.getApplication(testApplicationId);
        assertEq(uint256(app.status), uint256(TypeCertificate.CertificateStatus.Certified));
    }
    function test_ShouldAllowRegulatoryAuthorityToRejectApplication() public {
        vm.prank(manufacturer);
        typeCertificate.submitApplication(initialIpfsCID, initialDroneSpecHash);

        vm.prank(regulatoryAuthority);
        typeCertificate.rejectApplication(testApplicationId);

        TypeCertificate.Application memory app = typeCertificate.getApplication(testApplicationId);
        assertEq(uint256(app.status), uint256(TypeCertificate.CertificateStatus.Rejected));
    }
}
