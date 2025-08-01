# Install deps
npm i ethers@5

# Run on Sepolia (example) with inclusion latency only
node bench_type_cert.js \
  --rpc $SEPOLIA_RPC \
  --addr $TYPE_CERT_ADDR \
  --pk-reg $PK_REGULATOR \
  --pk-mfr $PK_MANUFACTURER \
  --pk-nb  $PK_NOTIFIED_BODY \
  --n 1000 --c 25 --confs 0 \
  --run-id sepolia_W1_N1000_C25_r1 \
  --network sepolia --rollup none \
  --out benchmarks.csv
