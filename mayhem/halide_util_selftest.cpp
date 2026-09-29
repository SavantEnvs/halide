// Known-answer behavioral oracle for the Halide string utilities exercised by the
// fuzz targets (src/Util.cpp). AUTHORED for the Mayhem integration: the upstream
// test suite (test/, ctest) requires a full LLVM-21 libHalide build which is out of
// scope for this focused commit image, so this oracle asserts golden outputs of the
// exact functions on the fuzzed code path. Prints one "PASS <name>"/"FAIL <name>"
// line per check plus a final summary; exit code = number of failures.
#include <cstdio>
#include <string>
#include <vector>

#include "Util.h"

using namespace Halide::Internal;

static int failures = 0;
static int passes = 0;

static void check(const char *name, bool ok) {
    if (ok) {
        printf("PASS %s\n", name);
        passes++;
    } else {
        printf("FAIL %s\n", name);
        failures++;
    }
}

int main() {
    // strip_namespaces
    check("strip_simple", strip_namespaces("foo") == "foo");
    check("strip_one_ns", strip_namespaces("ns::foo") == "foo");
    check("strip_nested_ns", strip_namespaces("a::b::c::foo") == "foo");
    check("strip_trailing", strip_namespaces("a::") == "");
    check("strip_empty", strip_namespaces("") == "");
    check("strip_only_sep", strip_namespaces("::") == "");
    check("strip_leading", strip_namespaces("::foo") == "foo");

    // extract_namespaces
    {
        std::vector<std::string> ns;
        std::string base = extract_namespaces("a::b::c", ns);
        check("extract_base", base == "c");
        check("extract_count", ns.size() == 2);
        check("extract_ns0", ns.size() == 2 && ns[0] == "a");
        check("extract_ns1", ns.size() == 2 && ns[1] == "b");
    }
    {
        std::vector<std::string> ns;
        std::string base = extract_namespaces("plain", ns);
        check("extract_plain_base", base == "plain");
        check("extract_plain_empty", ns.empty());
    }

    // split_string
    {
        std::vector<std::string> v = split_string("a,b,c", ",");
        check("split_basic", v.size() == 3 && v[0] == "a" && v[1] == "b" && v[2] == "c");
    }
    {
        std::vector<std::string> v = split_string("a,,c", ",");
        check("split_empty_mid", v.size() == 3 && v[1] == "");
    }
    {
        std::vector<std::string> v = split_string("a,", ",");
        check("split_trailing_delim", v.size() == 2 && v[0] == "a" && v[1] == "");
    }
    {
        std::vector<std::string> v = split_string("", ",");
        check("split_empty_input", v.size() == 1 && v[0] == "");
    }
    {
        std::vector<std::string> v = split_string("nodelim", ",");
        check("split_no_delim", v.size() == 1 && v[0] == "nodelim");
    }
    {
        std::vector<std::string> v = split_string("x::y::z", "::");
        check("split_multichar", v.size() == 3 && v[0] == "x" && v[2] == "z");
    }

    // starts_with / ends_with / replace_all
    check("starts_with_true", starts_with("halide_rocks", "halide"));
    check("starts_with_false", !starts_with("halide", "halide_rocks"));
    check("starts_with_empty", starts_with("anything", ""));
    check("ends_with_true", ends_with("file.cpp", ".cpp"));
    check("ends_with_false", !ends_with("file.cpp", ".h"));
    check("replace_all_basic", replace_all("a.b.c", ".", "::") == "a::b::c");
    check("replace_all_none", replace_all("abc", "x", "y") == "abc");

    // c_print_name (also in Util.cpp, pure)
    check("c_print_name_ns", c_print_name("a::b", true) == "_a______b");
    check("c_print_name_dot", c_print_name("f.x", true) == "_f_x");
    check("c_print_name_dollar", c_print_name("v$1", true) == "_v__1");

    printf("SELFTEST TOTAL=%d PASSED=%d FAILED=%d\n", passes + failures, passes, failures);
    return failures == 0 ? 0 : 1;
}
