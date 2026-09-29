// In-process libFuzzer harness for tools/build_halide_h.cpp (target `build-halide-h`).
// Converted from the raw file-input CLI form (which yielded 0 edges under Mayhem's
// tracer) to an in-process harness over the SAME code path: real main() -> dump_header()
// recursion, include-resolution and line parsing, unchanged upstream source included below.
//
// The tool requires every transitively-included header to be listed on the command line
// (else abort()) and to exist (else exit(1)). The harness mirrors a valid invocation:
// it scans the fuzzed input for `#include "name"` lines, materializes each named file
// (empty) in a scratch dir and lists it, exactly as the Makefile does for Halide.h.
// Inputs whose include names can't be valid filenames are rejected up front.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unistd.h>
#include <vector>

#define main build_halide_h_main
#include "../tools/build_halide_h.cpp"
#undef main

static const char *g_dir = nullptr;

static bool valid_name(const std::string &n) {
    if (n.empty() || n.size() > 200) return false;
    if (n == "." || n == "..") return false;
    for (char c : n) {
        if (c == '/' || c == '\\' || c == '\0') return false;
    }
    if (n.find("runtime_internal") != std::string::npos) return false;  // handled before listing
    return true;
}

static void ensure_init() {
    if (g_dir) return;
    // Per-process scratch dir, under TMPDIR when the sandbox sets one: concurrent Mayhem workers
    // materialize header files under their own names here.
    const char *env = getenv("TMPDIR");
    std::string base = (env && *env) ? env : "/tmp";
    while (base.size() > 1 && base.back() == '/') base.pop_back();
    static std::string dir_template;
    dir_template = base + "/bhh_fuzz_XXXXXX";
    g_dir = mkdtemp(&dir_template[0]);
    if (!g_dir) abort();
    // The tool streams the assembled header to stdout; discard it in-process.
    static const char *kSink = "/dev/null";
    if (!freopen(kSink, "w", stdout)) abort();
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    ensure_init();
    if (size > (1 << 16)) return 0;
    std::string input(reinterpret_cast<const char *>(data), size);
    if (input.find('\0') != std::string::npos) return 0;

    // Collect `#include "name"` names the same way the tool parses them (start of line).
    std::vector<std::string> subs;
    const std::string inc = "#include \"";
    size_t pos = 0;
    while (pos <= input.size()) {
        size_t eol = input.find('\n', pos);
        std::string line = input.substr(pos, eol == std::string::npos ? std::string::npos : eol - pos);
        if (line.size() >= 1000) return 0;  // fgets in the tool splits >1023-char lines; keep parses aligned
        if (line.compare(0, inc.size(), inc) == 0) {
            std::string name = line.substr(inc.size());
            size_t q = name.find('"');
            // Backport note: the live mayhem branch rejects a missing closing quote here (`return
            // 0`), which screens out exactly the inputs that reach tools/build_halide_h.cpp's own
            // stale-header abort() (dump_header()'s char line[1024] is reused, unindexed, across
            // fgets() calls, so its quote scan can walk into a previous iteration's leftover bytes
            // and split the name differently than this harness's newline-bounded parse does — a
            // real, reachable defect in the tool, mayhemheroes run 9's CWE-20 finding). Restored to
            // the original mayhemheroes harness's behavior (no reject) so that finding reproduces.
            if (q != std::string::npos) name.resize(q);
            if (!valid_name(name)) return 0;  // reject: would be an invalid CLI invocation
            subs.push_back(name);
        }
        if (eol == std::string::npos) break;
        pos = eol + 1;
    }
    if (subs.size() > 32) return 0;

    std::string dir(g_dir);
    std::string lic = dir + "/license.txt";
    std::string hdr = dir + "/input.h";
    {
        FILE *f = fopen(lic.c_str(), "w");
        if (!f) return 0;
        fputs("fuzz license\n", f);
        fclose(f);
        f = fopen(hdr.c_str(), "w");
        if (!f) return 0;
        fwrite(input.data(), 1, input.size(), f);
        fclose(f);
    }
    std::vector<std::string> created;
    for (const std::string &s : subs) {
        std::string p = dir + "/" + s;
        FILE *f = fopen(p.c_str(), "w");
        if (!f) return 0;  // unmaterializable name: reject input
        fclose(f);
        created.push_back(p);
    }

    done.clear();
    listed.clear();
    std::vector<char *> argv;
    argv.push_back(const_cast<char *>("build_halide_h"));
    argv.push_back(const_cast<char *>(lic.c_str()));
    argv.push_back(const_cast<char *>(hdr.c_str()));
    for (const std::string &p : created) {
        argv.push_back(const_cast<char *>(p.c_str()));
    }
    build_halide_h_main(static_cast<int>(argv.size()), argv.data());

    for (const std::string &p : created) unlink(p.c_str());
    unlink(hdr.c_str());
    unlink(lic.c_str());
    return 0;
}
