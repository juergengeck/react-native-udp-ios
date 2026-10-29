import type { TurboModule } from 'react-native/Libraries/TurboModule/RCTExport';
import { TurboModuleRegistry } from 'react-native';

// Define the structure for socket options expected by the native module
export interface UdpSocketOptionsSpec {
  type: string; // 'udp4' | 'udp6'
  reuseAddr: boolean;
  reusePort?: boolean; // Allow SO_REUSEPORT on supported platforms (macOS/iOS)
  broadcast: boolean;
  debug?: boolean;
  debugLabel?: string;
  direct?: boolean;
}

// Define the structure for bind info returned by the native module
export interface BindInfoSpec {
  address: string;
  port: number;
}

// Define options for send operation
export interface SendOptionsSpec {
  timeout?: number;
  ttl?: number;
}

// Define the main interface for the TurboModule
export interface Spec extends TurboModule {
  // Socket Management
  createSocket(options: UdpSocketOptionsSpec): Promise<{socketId: string}>; // Returns socket ID as string
  bind(socketId: string, port: number, address: string): Promise<BindInfoSpec>;
  close(socketId: string): Promise<void>;
  closeAllSockets(): Promise<{ closed: number }>;

  // Data Transmission
  send(socketId: string, base64Data: string, port: number, address: string, options?: SendOptionsSpec): Promise<void>;

  // Network Information
  getLocalIPAddresses(): string[]; // Returns array of local IP addresses
  address(socketId: string): Promise<{ address: string; port: number; family: string; bound?: boolean }>;

  // Socket option (basic) – advanced opts handled by JSI now
  setBroadcast(socketId: string, flag: boolean): Promise<void>;
  
  // Event Handling
  setDataEventHandler(socketId: string): Promise<void>;
  
  // Optional: For releasing ports if needed
  forciblyReleasePort?(port: number): Promise<{ success: boolean }>;

  // Event Emitter support (Native -> JS)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
  
  // Constants
  getConstants(): {
    VERSION: string;
    TURBO_ENABLED: boolean;
  };
}

// Export the TurboModule
export default TurboModuleRegistry.get<Spec>('NativeUDPDirectModule'); 