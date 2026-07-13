#include <climits>
#include <stdint.h>
#include <stdio.h>

#include <fuzzer/FuzzedDataProvider.h>

namespace Halide {
namespace Internal {
std::string strip_namespaces(const std::string &name);

}
}  // namespace Halide

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    FuzzedDataProvider provider(data, size);
    std::string name = provider.ConsumeRandomLengthString();

    Halide::Internal::strip_namespaces(name);

    return 0;
}
