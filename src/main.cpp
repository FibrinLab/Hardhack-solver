#include <iostream>
#include <string>
#include <vector>
#include <memory>
#include "miner.h"
#include "compute.h"

void print_usage(const char* prog_name) {
    std::cerr << "Usage: " << prog_name << " [-n iterations] [--json] [--cpu]" << std::endl;
}

int main(int argc, char* argv[]) {
    int iterations = 1000;  // Default iterations
    bool json_output = false;
    bool force_cpu = false;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-n" && i + 1 < argc) {
            iterations = std::stoi(argv[++i]);
        } else if (arg == "--json") {
            json_output = true;
        } else if (arg == "--cpu") {
            force_cpu = true;
        } else {
            print_usage(argv[0]);
            return 1;
        }
    }

    std::unique_ptr<ComputeDevice> device;

#ifdef ENABLE_TT
    if (!force_cpu) {
        device = create_tt_compute();
    } else {
        device = create_cpu_compute();
    }
#else
    device = create_cpu_compute();
#endif

    HardHackMiner miner(std::move(device));
    miner.mine(iterations, json_output);

    return 0;
}