#pragma once

// This is a minimal TurboModule implementation that delegates to JSI for performance-critical operations

#include <ReactCommon/TurboModule.h>
#include <ReactCommon/TurboModuleUtils.h>
#include <jsi/jsi.h>
#include <memory>

#ifdef __OBJC__
@class UDPSocketManager;
#endif

namespace facebook {
namespace react {

class UDPDirectModuleMinimal : public TurboModule {
public:
    explicit UDPDirectModuleMinimal(std::shared_ptr<CallInvoker> jsInvoker);
    virtual ~UDPDirectModuleMinimal();
    
    // Minimal TurboModule methods - only what's absolutely necessary
    static std::string getName() { return "UDPDirectModule"; }
    
    // Install JSI bindings
    void installJSI(jsi::Runtime& runtime);
    
    // Set socket manager
    void setSocketManager(void* socketManager);
    
private:
    void* socketManager_;
    std::shared_ptr<CallInvoker> jsInvoker_;
    bool jsiInstalled_;
};

} // namespace react
} // namespace facebook