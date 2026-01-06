#pragma once
#include <cstdint>
#include <memory>
#include <string>

// Dimensions from organizers
constexpr int M = 16;
constexpr int K = 50240;
constexpr int N = 16; 

class ComputeDevice {
public:
    virtual ~ComputeDevice() = default;
    
    // Updated types per organizer spec:
    // A: unsigned u8
    // B: signed i8
    // C: signed i32 (16x16)
    virtual void matmul(const uint8_t* A, 
                       const int8_t* B, 
                       int32_t* C) = 0;

    virtual std::string name() const = 0;
};

std::unique_ptr<ComputeDevice> create_cpu_compute();

#ifdef ENABLE_TT
std::unique_ptr<ComputeDevice> create_tt_compute();
#endif