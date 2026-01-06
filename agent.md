Amadeus Hard Hack Kernel instructions

there are instruction from the developer docs 
"HARD HACK — RISC-V BENCHMARKING COMPETITION
The Hard Hack focuses on low-level performance engineering using RISC-V workloads and upcoming AMA compute primitives.
Environment Setup
Which architecture are we targeting?
The benchmarking infrastructure will be executed on:
● RISC-V chips (TensTorrent-class hardware)
Exact microarchitecture and specs will be released before Day 1.
What is the expected input/output format?
Two workload types:
1. Matrix Multiplication (MatMul)
● Fixed matrix sizes (to be provided)
● Required precision (fp32/fp16/int8)
● Expected output: execution metrics + result hash
2. AMA Workloads (Task-Specific)
These may include:
● Convolution kernels
● Attention-style workloads
● Small model inference microbenchmarks
Documentation for each workload will include:
● Input schema
● Output schema
● Time/memory expectations
Reference Docs
Validator setup & node info: https://docs.ama.one/validator/running-a-node
API Reference
Endpoints for submitting benchmark results, fetching workloads, pulling validation results will be released prior to start.
What do submissions include?
Every submission must include:
● Raw metrics (latency, throughput, ops/sec)
● Correctness proof / output hash
● Docker container for reproducibility
● Source code or compiled binary
● Benchmark metadata (compiler flags, libraries used, etc.)
Environment & Constraints
● Hardware: RISC-V chips (TensTorrent) or GPU-based simulation
● Data types: Provided with workload
● Time limits: Strict (per workload)
● Memory limits: Enforced
● Caching: Allowed (in this iteration)
Are caching or precomputation allowed?
Yes, caching is allowed as long as workload input is not modified.
Number of submissions per day?
Unlimited.
Do I have to containerize my submission?
Optional, but recommended for full reproducibility.
Submission Workflow
1. Request API Key
2. Receive Workload Spec
3. Run Locally / Optimize
4. Submit via JSON or Upload Container
5. Receive Score
6. Optional Validation Run
7. Score Locked to Leaderboard

Evaluation & Scoring
Criteria
● Latency (primary)
● Throughput
● Correctness
● Resource usage (optional depending on workload)
Miner competition scoring is based on: ✔ valid-sols / second
ZK-style tasks may include: ✔ novelty + correctness weighting
Scoring Formula
Released with workloads. Likely:
score = weighted(latency, throughput, correctness)
Tie-Break Rules
1. Lowest latency
2. Lowest memory usage
3. Earliest submission timestamp

Are optimized libraries allowed?
Yes:
● BLIS
● OpenBLAS
● TVM
● Custom kernels"


Also one of the judges asked my this "can you try to submit the solution to testnet?
is it accepted?" so i wonder if i need to build this into and actual miner for the testnet. so other messages from the judges "it should be like atleasdt 200-300k solved matrixes per second
a laptop GPU gets that much", ""yes full solves
a 4090 gets around 1.2m
achieveing even 10% of a 4090 is reasonable
"

so those are the rules,
1. I have a koyeb instance i can use for testing
2. Submission should be dockerised with clear metrics logs
3. i believe seeds gotten from testnet and correctness validated against it
4. C++ would be preferable
5. use an optimisation library.
6. Make this fast. i think tenstorret chip is RISCV with an AI GPU acceleration, wire it to use the accelerator.

Thanks
