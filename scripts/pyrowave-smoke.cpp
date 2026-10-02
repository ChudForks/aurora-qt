// SPDX-License-Identifier: GPL-3.0-or-later
// Native wire-layout and headless Vulkan pipeline initialization test.
#include "pyrowave_vk.h"
#include "pyrowave/pyrowave_decoder.h"
#include <cstring>
#include <iostream>

int main()
{
    PyroWave::BitstreamSequenceHeader header{};
    header.width_minus_1 = 127;
    header.height_minus_1 = 127;
    header.sequence = 5;
    header.extended = 1;
    header.total_blocks = 42;
    header.chroma_resolution = 1;
    uint32_t words[2]{};
    std::memcpy(words, &header, sizeof words);
    if (words[0] != (127u | (127u << 14) | (5u << 28) | (1u << 31)) ||
        words[1] != (42u | (1u << 26))) {
        std::cerr << "FAIL: PyroWave wire-layout mismatch\n";
        return 1;
    }
    std::cout << "PASS: PyroWave little-endian sequence-header layout\n";
    auto context = pyrowave_vk::context::create();
    if (!context) {
        std::cout << "UNVERIFIED: Vulkan context unavailable on this runner\n";
        return 77;
    }
    std::cout << "GPU: " << context->phys_dev.getProperties().deviceName.data() << '\n';
    try {
        PyroWave::Decoder decoder(context->phys_dev, context->dev, 128, 128,
                                 PyroWave::ChromaSubsampling::Chroma420, true);
        PyroWave::DecoderInput input(decoder);
        std::cout << "PASS: PyroWave decoder and Vulkan shader pipelines initialized\n"
                     "UNVERIFIED: frame execution, swapchain, and host streaming\n";
    } catch (const std::exception& e) {
        std::cerr << "Decoder initialization failed: " << e.what() << '\n';
        const std::string error = e.what();
        if (error.find("Missing ") != std::string::npos ||
            error.find("missing subgroup") != std::string::npos ||
            error.find("required subgroup") != std::string::npos) {
            return 77;
        }
        return 1;
    }
    return 0;
}
