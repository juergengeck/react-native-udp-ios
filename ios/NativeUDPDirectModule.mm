#import "NativeUDPDirectModule.h"
#import "UDPDirectModuleCxxImpl.h"
#import "UDPDirectJSI.h"
#import "UDPSocketManager.h"
#import <React/RCTBridge+Private.h>
#import <ReactCommon/TurboModule.h>
#import <ReactCommon/TurboModuleUtils.h>
#import <ReactCommon/CallInvoker.h>
#import <jsi/jsi.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import <ReactCodegen/UDPDirectModuleSpec/UDPDirectModuleSpec.h>
#endif

using namespace facebook::react;

@implementation NativeUDPDirectModule {
    std::shared_ptr<UDPDirectModuleCxxImpl> _cppImpl;
    UDPSocketManager *_socketManager;
    BOOL _jsiInstalled;
    NSTimeInterval _moduleCreationTime;
}

RCT_EXPORT_MODULE()

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"onMessage", @"onError", @"onClose"];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSLog(@"[NativeUDPDirectModule] Initialized as TurboModule provider");

        // Record module creation time for detecting reloads
        _moduleCreationTime = [[NSDate date] timeIntervalSince1970];

        // Create socket manager early
        dispatch_queue_t udpQueue = dispatch_queue_create("com.lama.udp.socket.queue", DISPATCH_QUEUE_SERIAL);
        _socketManager = [[UDPSocketManager alloc] initWithDelegateQueue:udpQueue];
        _jsiInstalled = NO;

        NSLog(@"[NativeUDPDirectModule] Module created at time: %.0f", _moduleCreationTime);
    }
    return self;
}

- (void)setBridge:(RCTBridge *)bridge {
    [super setBridge:bridge];
    
    // Install JSI bindings when bridge is available
    if (!_jsiInstalled) {
        RCTCxxBridge *cxxBridge = (RCTCxxBridge *)bridge;
        if (cxxBridge.runtime) {
            facebook::jsi::Runtime *runtime = (facebook::jsi::Runtime *)cxxBridge.runtime;
            if (runtime) {
                // Get the CallInvoker from the bridge
                auto callInvoker = bridge.jsCallInvoker;
                if (callInvoker) {
                    UDPDirectJSI::install(*runtime, (__bridge void *)_socketManager, callInvoker);
                    _jsiInstalled = YES;
                    NSLog(@"[NativeUDPDirectModule] JSI bindings installed successfully");
                } else {
                    NSLog(@"[NativeUDPDirectModule] Failed to get JS CallInvoker");
                }
            }
        }
    }
}

#pragma mark - RCTTurboModule

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
    NSLog(@"[NativeUDPDirectModule] Creating TurboModule with C++ implementation");

    _cppImpl = std::make_shared<UDPDirectModuleCxxImpl>(params.jsInvoker);

    // Pass socket manager to C++ implementation for JSI installation
    if (_socketManager) {
        _cppImpl->setSocketManager((__bridge void *)_socketManager);
    }

    return std::static_pointer_cast<facebook::react::TurboModule>(_cppImpl);
}

#pragma mark - Cleanup

- (void)invalidate {
    NSLog(@"[NativeUDPDirectModule] invalidate called - JS context is being destroyed");

    // Clean up all sockets synchronously to prevent crashes on reload
    if (_socketManager) {
        // Use the synchronous version to ensure complete cleanup before JS reload
        dispatch_sync(_socketManager.delegateQueue, ^{
            [self->_socketManager closeAllSocketsSynchronously];
        });
        NSLog(@"[NativeUDPDirectModule] All sockets closed synchronously");
    }

    // Reset JSI installation flag so it reinstalls on next bridge setup
    _jsiInstalled = NO;

    // Clear C++ implementation
    if (_cppImpl) {
        _cppImpl.reset();
    }

    NSLog(@"[NativeUDPDirectModule] Module invalidation complete");
}

- (void)dealloc {
    NSLog(@"[NativeUDPDirectModule] dealloc called");
    // Additional cleanup if needed, but invalidate should handle most of it
}

@end