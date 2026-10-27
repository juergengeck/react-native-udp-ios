/**
 * UDPDirectModuleCompat.mm
 * 
 * Compatibility implementation for UDPDirectModule to ensure proper linking of C++ standard library features
 * when building with newer Xcode versions that might have different C++ standards support.
 */

#include "UDPDirectModuleCompat.h"

// This file exists primarily to ensure proper linking of C++ standard library features
// needed by TurboModules. The implementation is intentionally minimal since the real
// functionality is in the header file.

namespace UDPDirectModuleCompat {
namespace Compat {

// Implementation is in the header file as an inline function
// This is just a dummy function to ensure the namespace exists at link time
bool __DummyFunction() {
    return true;
}

}} // namespace UDPDirectModuleCompat::Compat 