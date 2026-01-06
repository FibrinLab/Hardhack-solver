#pragma once
#include <cstdint>
#include <memory>
#include <string>

constexpr int M = 16;
constexpr int K = 50240;
constexpr int N = 16;

class ComputeDevice {
public:
    virtual ~ComputeDevice() = default;
    
    // Use raw pointers to avoid vector overhead in the hot loop
    virtual void matmul(const uint8_t* A, 
                       const uint8_t* B, 
                       uint8_t* C) = 0;

    virtual std::string name() const = 0;
};

std::unique_ptr<ComputeDevice> create_cpu_compute();

#ifdef ENABLE_TT
std::unique_ptr<ComputeDevice> create_tt_compute();
#endif
