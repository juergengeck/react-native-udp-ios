import { NativeModules, Platform } from 'react-native';
import UDPDirectModuleNative, { type Spec } from './NativeUDPDirectModule';

const LINKING_ERROR =
  `The package 'react-native-udp-direct' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo managed workflow\n';

// Use the TurboModule if available, otherwise fallback to NativeModules
const UDPDirectModule = UDPDirectModuleNative || NativeModules.NativeUDPDirectModule
  ? (UDPDirectModuleNative || NativeModules.NativeUDPDirectModule)
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR);
        },
      }
    );

// Note: JSI methods like sendDirect are installed globally and not part of the TurboModule spec
// They can be accessed via the global object or through the JSI wrapper

export default UDPDirectModule as Spec;

// Re-export types for convenience
export type {
  Spec as UDPDirectModuleSpec,
  UdpSocketOptionsSpec,
  BindInfoSpec,
  SendOptionsSpec,
} from './NativeUDPDirectModule';

// Export event names
export const UDP_EVENTS = {
  MESSAGE: 'onMessage',
  ERROR: 'onError',
  CLOSE: 'onClose',
} as const;

// Export JSI wrapper for high-performance usage
export { 
  UDPSocketJSI, 
  createUDPSocket, 
  isJSIAvailable,
  type UDPSocketOptions,
  type UDPMessageEvent,
  type UDPErrorEvent,
  type UDPCloseEvent
} from './jsi-wrapper';