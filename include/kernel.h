#pragma once

#include <vector>
#include <cstdint>
#include <iostream>

#ifdef __APPLE__
#include <Accelerate/Accelerate.h>
#else
#include <cblas.h>
#endif

// Abstract base class for Compute Kernels
class Kernel {
public:
    virtual ~Kernel() = default;
    virtual void run(int M, int N, int K, const float* alpha, const float* A, int lda, const float* B, int ldb, const float* beta, float* C, int ldc) = 0;
    virtual std::string name() const = 0;
};

// CPU implementation using OpenBLAS
class OpenBLASKernel : public Kernel {
public:
    void run(int M, int N, int K, const float* alpha, const float* A, int lda, const float* B, int ldb, const float* beta, float* C, int ldc) override {
        // cblas_sgemm calculates C = alpha * A * B + beta * C
        // We assume RowMajor order for standard C++ arrays
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, 
                    M, N, K, 
                    *alpha, A, lda, 
                    B, ldb, 
                    *beta, C, ldc);
    }

    std::string name() const override {
        return "OpenBLAS_CPU";
    }
};

// Placeholder for Tenstorrent/Accelerator Kernel
class AcceleratorKernel : public Kernel {
public:
    void run(int M, int N, int K, const float* alpha, const float* A, int lda, const float* B, int ldb, const float* beta, float* C, int ldc) override {
        // TODO: Integrate Tenstorrent tt-metal or similar API here
        // For now, fallback to BLAS or throw error
        std::cerr << "Accelerator not yet implemented!" << std::endl;
    }

    std::string name() const override {
        return "Tenstorrent_Accelerator";
    }
};
