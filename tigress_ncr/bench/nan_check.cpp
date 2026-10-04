// NaN-semantics check for the build flags (run by build_tigress.sh).
//
// tigris relies on NaN tests as safety nets: std::isnan in the C2P density/pressure
// floors, CR-FOFC, CRAverage, the CR implicit source and the NCR solver bail-out, and the
// x != x / !(x >= 0) idioms elsewhere. Flags that assume finite math (icpx
// -fp-model=fast=2, GCC/Clang -ffast-math without -fno-finite-math-only) compile all of
// these to "false", and fold x/x to 1. This program computes a NaN at run time and
// prints whether each test still sees it; build_tigress.sh refuses flags that fail it.
#include <cmath>
#include <cstdio>
#include <cstdlib>
__attribute__((noinline)) bool by_isnan(double x) { return std::isnan(x); }
__attribute__((noinline)) bool by_compare(double x) { return !(x >= 0.0); }
__attribute__((noinline)) bool by_self(double x) { return x != x; }
int main(int argc, char **argv) {
  double z = std::atof(argc > 1 ? argv[1] : "0");
  double x = z/z;  // NaN, unknown to the compiler
  int ok = by_isnan(x) && by_compare(x) && by_self(x);
  std::printf("nan_checks=%s isnan=%d !(x>=0)=%d x!=x=%d\n", ok ? "kept" : "REMOVED",
              by_isnan(x), by_compare(x), by_self(x));
  return ok ? 0 : 1;
}
