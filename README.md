# A Blockchain-Driven Solution for UAV Certification

The UAV Certification and Passport NFT System is designed to streamline the certification process for Unmanned Aerial Vehicles (UAVs). By leveraging blockchain technology and Non-Fungible Tokens (NFTs), this system ensures secure, transparent, and tamper-proof management of UAV certifications and passports.

![System Architecture](asstes/System_Architecture.png)

## Features

- UAV Passport NFTs: Unique digital passports representing individual UAVs, storing metadata such as serial numbers, ownership, and certifications.
- Type Certification: Facilitating the process for submitting, reviewing, updating, and approving Type Certificates for UAV designs.
- Airworthiness Certification: Automated process for submitting, reviewing, and approving UAV airworthiness applications.
- Certificate NFTs: Digitally minted certificates linked to UAV Passport NFTs, ensuring verifiable authenticity.
- Role-Based Access Control: Distinct roles for manufacturers, regulatory authorities, and notified bodies to manage permissions and operations securely.
- Comprehensive Testing: Automated scripts to test the entire workflow, ensuring reliability and robustness.

## Repo

This workspace contains 3 directories:

1. 'contracts': Holds the 4 contracts: TypeCertificat, UAVPassportNFT, Airworthiness, and CertificateNFT. It also has the library CertificateTypes enabling common enums across contracts.
2. 'scripts': Contains a script needed for deploying contracts with the ethers library
3. 'tests': Contains two test scripts to test the functionality of the full system.

## Citation

If you use this repository please cite our paper:
```
@article{HASSAN2025165,
    title = {Blockchain and NFT-based digital passports for UAV preoperational certification},
    journal = {Internet of Things and Cyber-Physical Systems},
    volume = {5},
    pages = {165-184},
    year = {2025},
    issn = {2667-3452},
    doi = {https://doi.org/10.1016/j.iotcps.2026.03.003},
    url = {https://www.sciencedirect.com/science/article/pii/S2667345226000039},
    author = {Abduraouf Hassan and Ahmad Musamih and Khaled Salah and Ernesto Damiani and Mohammed Omar and Dragan Boscovic and Ibrar Yaqoob}
}
```
