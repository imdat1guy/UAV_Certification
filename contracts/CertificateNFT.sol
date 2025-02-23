// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./CertificateTypes.sol";

interface AirworthinessInterface {
    function regulatoryAuthority() external view returns (address);
    function isCertified(uint256 applicationId) external view returns (bool);
}

contract CertificateNFT is ERC721URIStorage, AccessControl {
    using CertificateTypes for CertificateTypes.CertificateType;
    uint256 public certificateCounter;

    bytes32 public constant AUTHORITY_ROLE = keccak256("AUTHORITY_ROLE");

    struct CertificateData {
        uint256 tokenId;
        CertificateTypes.CertificateType ctype;
        address issuer;
        bool isValid;
        address linkedContract;        // Address of the Certification application contract (Airworthiness)
        uint256 linkedApplicationId;   // Application ID in the contract
    }

    mapping(uint256 => CertificateData) public certificateData;

    event CertificateMinted(
        uint256 indexed tokenId,
        CertificateTypes.CertificateType indexed ctype,
        address issuer,
        string metadataURI
    );

    event CertificateRevoked(uint256 indexed tokenId, address issuer);

    constructor() ERC721("CertificateNFT", "CNFT") {
        certificateCounter = 0;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Override supportsInterface due to multiple inheritance
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721URIStorage, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    modifier onlyAuthority() {
        require(hasRole(AUTHORITY_ROLE, msg.sender), "Caller is not an authority");
        _;
    }

    // Function to add a regulatory authority
    function addAuthority(address authority) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
        grantRole(AUTHORITY_ROLE, authority);
    }

    // Authority mints Certificate NFT
    function mintCertificate(
        string memory metadataURI,
        CertificateTypes.CertificateType ctype,
        address issuer,
        address linkedContract,
        uint256 linkedApplicationId
    ) external onlyAuthority {

        if(ctype == CertificateTypes.CertificateType.Airworthiness){
            // Create an instance of the Airworthiness contract interface
            AirworthinessInterface airworthiness = AirworthinessInterface(linkedContract);

            // Verify that msg.sender is the regulatoryAuthority of the linked Airworthiness contract
            require(msg.sender == airworthiness.regulatoryAuthority(), "Caller is not the regulatory authority of the linked contract");

            // Check that the applicationId exists in the Airworthiness contract
            require(airworthiness.isCertified(linkedApplicationId), "Application ID does not exist in the linked contract");
        }
        
        //mint the certificate
        certificateCounter++;
        uint256 tokenId = certificateCounter;

        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, metadataURI);

        // Store certificate data with references
        certificateData[tokenId] = CertificateData({
            tokenId: tokenId,
            ctype: ctype,
            issuer: issuer,
            isValid: true,
            linkedContract: linkedContract,
            linkedApplicationId: linkedApplicationId
        });

        emit CertificateMinted(tokenId, ctype, issuer, metadataURI);
    }

    // Retrieve CertificateType
    function getCertificateType(uint256 tokenId) external view returns (CertificateTypes.CertificateType) {
        require(_tokenExists(tokenId), "Certificate does not exist");
        return certificateData[tokenId].ctype;
    }

    // Retrieve issuer
    function getIssuer(uint256 tokenId) external view returns (address) {
        require(_tokenExists(tokenId), "Certificate does not exist");
        return certificateData[tokenId].issuer;
    }

    // Check if the certificate is currently valid
    function isValid(uint256 tokenId) external view returns (bool) {
        require(_tokenExists(tokenId), "Certificate does not exist");
        return certificateData[tokenId].isValid;
    }

    // Internal function to check if a token exists
    function _tokenExists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    // Issuer revokes the certificate
    function revokeCertificate(uint256 tokenId) external {
        require(_tokenExists(tokenId), "Certificate does not exist");

        CertificateData storage data = certificateData[tokenId];

        // Ensure that only the issuer can revoke the certificate
        require(msg.sender == data.issuer, "Only the issuer can revoke this certificate");

        // Set isValid to false
        data.isValid = false;

        emit CertificateRevoked(tokenId, msg.sender);
    }
}