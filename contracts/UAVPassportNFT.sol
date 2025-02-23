// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./CertificateNFT.sol"; // 
import "./CertificateTypes.sol";

contract UAVPassportNFT is ERC721, AccessControl, IERC721Receiver {
    using Strings for uint256;
    using CertificateTypes for CertificateTypes.CertificateType;

    bytes32 public constant MANUFACTURER_ROLE = keccak256("MANUFACTURER_ROLE");
    bytes32 public constant AUTHORITY_ROLE = keccak256("AUTHORITY_ROLE");

    uint256 public tokenCounter;

    struct LinkedCertificate {
        address certificateContract;
        uint256 certificateTokenId;
        CertificateTypes.CertificateType ctype;
    }

    struct UAVData {
        uint256 tokenId;
        string serialNumber;
        address typeCertificateContract;
        uint256 typeCertificateApplicationId;
        string ipfsMetadataCID;
        address owner;
    }

    mapping(uint256 => UAVData) public uavData;
    mapping(uint256 => LinkedCertificate[]) public linkedCertificates;
    mapping(uint256 => string[]) public importExportTrace;

    event UAVMinted(uint256 indexed tokenId, address indexed manufacturer, string ipfsMetadataCID);
    event CertificateLinked(uint256 indexed tokenId, CertificateTypes.CertificateType indexed ctype, address certificateContract, uint256 certificateTokenId);
    event OwnershipTransferred(uint256 indexed tokenId, address indexed previousOwner, address indexed newOwner);
    event ImportRejected(uint256 indexed tokenId, string reason);
    event MetadataUpdated(uint256 indexed tokenId, string ipfsMetadataCID);
    event ImportExportRecorded(uint256 indexed tokenId, string jurisdictionIdentifier);

    constructor() ERC721("UAVPassport", "UAVP") {
        tokenCounter = 0;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    modifier onlyManufacturer() {
        require(hasRole(MANUFACTURER_ROLE, msg.sender), "Caller is not a manufacturer");
        _;
    }

    modifier onlyAuthority() {
        require(hasRole(AUTHORITY_ROLE, msg.sender), "Caller is not an authority");
        _;
    }

    function addManufacturer(address manufacturer) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
        grantRole(MANUFACTURER_ROLE, manufacturer);
    }

    function addAuthority(address authority) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
        grantRole(AUTHORITY_ROLE, authority);
    }

    function mintUAV(string memory serialNumber, address typeCertificateContract, uint256 typeCertificateApplicationId, string memory ipfsMetadataCID) external onlyManufacturer {
        tokenCounter++;
        uint256 tokenId = tokenCounter;

        _safeMint(msg.sender, tokenId);
        uavData[tokenId] = UAVData(tokenId, serialNumber, typeCertificateContract, typeCertificateApplicationId, ipfsMetadataCID, msg.sender);

        emit UAVMinted(tokenId, msg.sender, ipfsMetadataCID);
    }

    function updateMetadata(uint256 tokenId, string memory ipfsMetadataCID) external {
        require(ownerOf(tokenId) == msg.sender, "Caller is not the owner");
        UAVData storage data = uavData[tokenId];
        data.ipfsMetadataCID = ipfsMetadataCID;

        emit MetadataUpdated(tokenId, ipfsMetadataCID);
    }

    function linkCertificate(uint256 uavTokenId, address certificateContractAddress, uint256 certificateTokenId) external onlyAuthority {
        require(_tokenExists(uavTokenId), "UAV token does not exist");

        CertificateNFT certificate = CertificateNFT(certificateContractAddress);

        // Ensure the caller is the owner of the CertificateNFT
        require(certificate.ownerOf(certificateTokenId) == msg.sender, "Caller is not the owner of the CertificateNFT");

        // Get the CertificateType from the CertificateNFT
        CertificateTypes.CertificateType ctype = certificate.getCertificateType(certificateTokenId);

        // Record the linked certificate
        linkedCertificates[uavTokenId].push(LinkedCertificate({
            certificateContract: certificateContractAddress,
            certificateTokenId: certificateTokenId,
            ctype: ctype
        }));

        emit CertificateLinked(uavTokenId, ctype, certificateContractAddress, certificateTokenId);

                // Transfer the CertificateNFT to this contract
        certificate.safeTransferFrom(msg.sender, address(this), certificateTokenId);

    }



    function transferUAV(address to, uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Caller is not the owner");
        _transfer(msg.sender, to, tokenId);

        UAVData storage data = uavData[tokenId];
        address previousOwner = data.owner;
        data.owner = to;

        emit OwnershipTransferred(tokenId, previousOwner, to);
    }

    function rejectImport(uint256 tokenId, string memory reason) external onlyAuthority {
        require(_tokenExists(tokenId), "UAV token does not exist");
        emit ImportRejected(tokenId, reason);
    }

    function recordImportExport(uint256 tokenId, string memory jurisdictionIdentifier) external onlyAuthority {
        require(_tokenExists(tokenId), "UAV token does not exist");
        importExportTrace[tokenId].push(jurisdictionIdentifier);

        emit ImportExportRecorded(tokenId, jurisdictionIdentifier);
    }

    function getUAVData(uint256 tokenId) external view returns (UAVData memory) {
        require(_tokenExists(tokenId), "UAV token does not exist");
        return uavData[tokenId];
    }

    function getLinkedCertificates(uint256 tokenId) external view returns (LinkedCertificate[] memory) {
        require(_tokenExists(tokenId), "UAV token does not exist");
        return linkedCertificates[tokenId];
    }

    function getImportExportTrace(uint256 tokenId) external view returns (string[] memory) {
        require(_tokenExists(tokenId), "UAV token does not exist");
        return importExportTrace[tokenId];
    }

    function _tokenExists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
