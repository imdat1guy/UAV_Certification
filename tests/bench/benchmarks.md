# Benchmarking

## Prerquisites

To Run the Benchmark You will first need:

- Prepare an RPC node to communicate with the Sepolia Testnet (You can use Alchemy or Infura to avoid manual setups)
- Create 3 Sepolia Ethereum Accounts (Regulatory Authority, Manufacturer, Notified Body) and fund them with Eth using public faucets
- Deploy the Smart Contracts to the Sepolia network. *Ensure that the Regulatory Authority is the contract owner.*
- Have node installed

## Running the benchmark

First install the dependencies:
`npm i ethers@5`

Then run the script multiple times with different configurations for the the number of drones (n) and concurrency (c)

### Workflow 1 (Type Certification)

```bash
node bench_type_cert.js \
  --rpc $SEPOLIA_RPC \
  --addr $TYPE_CERT__SC_ADDR \
  --pk-reg $PK_REGULATOR \
  --pk-mfr $PK_MANUFACTURER \
  --pk-nb  $PK_NOTIFIED_BODY \
  --n 200 --c 10 --confs 0 \
  --run-id sepolia_W1_N200_C10_r1 \
  --network sepolia --rollup none \
  --out benchmarks.csv
```

replace the values for rpc, addr, pk-reg, pk-mfr, pk-nb.

### Workflow 2 (Mint UAV Passport NFT, Airworthiness Workflow, and Mint and link Certification)

```bash
node bench_uav_air_cert.js \
  --rpc  $SEPOLIA_RPC \
  --passport $UAVPassportAddr \
  --airworth $AirworthinessAddr \
  --cert     $CertificateNFTAddr \
  --pk-reg $PK_REGULATOR \
  --pk-mfr $PK_MANUFACTURER \
  --type-cert $TYPE_CERT__SC_ADDR \
  --type-app-id 1   \
  --n 200  --c 10 \
  --run-id sepolia_W2_N200_C10_r1 \
  --network sepolia --out benchmarks.csv
```

type-app-id is the application id of the approved type certificate for the manufactured UAVs.

## Generating Reports

After running the scripts with multiple configurations run:
`python analyze_benchmarks.py [--input benchmarks.csv] [--outdir out]`
