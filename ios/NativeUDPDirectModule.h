#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <ReactCommon/RCTTurboModule.h>

#ifdef RCT_NEW_ARCH_ENABLED
@protocol NativeUDPDirectModuleSpec;
#endif

#ifdef RCT_NEW_ARCH_ENABLED
@interface NativeUDPDirectModule : RCTEventEmitter <NativeUDPDirectModuleSpec>
#else
@interface NativeUDPDirectModule : RCTEventEmitter <RCTBridgeModule>
#endif

@end 