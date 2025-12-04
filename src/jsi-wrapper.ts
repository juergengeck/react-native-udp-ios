/**
 * JSI Wrapper for UDP Direct Module
 * 
 * This file provides a clean JavaScript interface to the JSI-based UDP functions.
 * It uses the global functions installed by UDPDirectJSI.
 */

declare global {
  // Global zero-copy send function
  function udpSendDirect(
    socketId: string,
    buffer: ArrayBuffer,
    offset: number,
    length: number,
    port: number,
    address: string
  ): void;

  // UDP JSI namespace
  const _udpJSI: {
    createSocket(options: { type?: string; reuseAddr?: boolean; broadcast?: boolean }): string;
    bind(socketId: string, port: number, address: string): void;
    close(socketId: string): void;
    setEventHandler(socketId: string, handlers: {
      onMessage?: (event: { socketId: string; data: ArrayBuffer; base64Data?: string; address: string; port: number }) => void;
      onError?: (event: { socketId: string; error: string }) => void;
      onClose?: (event: { socketId: string; error?: string }) => void;
    }): void;
  };
}

export interface UDPSocketOptions {
  type?: 'udp4' | 'udp6';
  reuseAddr?: boolean;
  broadcast?: boolean;
}

export interface UDPMessageEvent {
  socketId: string;
  data: ArrayBuffer; // Zero-copy ArrayBuffer
  base64Data?: string; // Optional base64 for backward compatibility
  address: string;
  port: number;
}

export interface UDPErrorEvent {
  socketId: string;
  error: string;
}

export interface UDPCloseEvent {
  socketId: string;
  error?: string;
}

/**
 * High-performance UDP socket class using JSI bindings
 */
export class UDPSocketJSI {
  private socketId: string | null = null;
  private handlers: {
    onMessage?: (event: UDPMessageEvent) => void;
    onError?: (event: UDPErrorEvent) => void;
    onClose?: (event: UDPCloseEvent) => void;
  } = {};

  /**
   * Create a new UDP socket
   */
  async create(options: UDPSocketOptions = {}): Promise<void> {
    if (this.socketId) {
      throw new Error('Socket already created');
    }

    // Ensure JSI is available
    if (typeof _udpJSI === 'undefined') {
      throw new Error('UDP JSI bindings not available. Make sure the native module is properly initialized.');
    }

    this.socketId = _udpJSI.createSocket({
      type: options.type || 'udp4',
      reuseAddr: options.reuseAddr ?? false,
      broadcast: options.broadcast ?? false,
    });
  }

  /**
   * Bind the socket to a port and address
   */
  async bind(port: number, address: string = '0.0.0.0'): Promise<void> {
    if (!this.socketId) {
      throw new Error('Socket not created');
    }

    _udpJSI.bind(this.socketId, port, address);
    
    // Set up event handlers if any are registered
    if (Object.keys(this.handlers).length > 0) {
      this.updateEventHandlers();
    }
  }

  /**
   * Send data using zero-copy transfer
   */
  async send(data: Uint8Array | ArrayBuffer, port: number, address: string): Promise<void> {
    if (!this.socketId) {
      throw new Error('Socket not created');
    }

    if (data instanceof ArrayBuffer) {
      // Send entire ArrayBuffer
      udpSendDirect(this.socketId, data, 0, data.byteLength, port, address);
    } else {
      // Send Uint8Array with proper offset and length
      // Cast to ArrayBuffer since SharedArrayBuffer is not expected in this context
      udpSendDirect(this.socketId, data.buffer as ArrayBuffer, data.byteOffset, data.byteLength, port, address);
    }
  }

  /**
   * Set event handlers
   */
  on(event: 'message', handler: (event: UDPMessageEvent) => void): void;
  on(event: 'error', handler: (event: UDPErrorEvent) => void): void;
  on(event: 'close', handler: (event: UDPCloseEvent) => void): void;
  on(event: string, handler: any): void {
    switch (event) {
      case 'message':
        // Wrap the handler to add debugging
        this.handlers.onMessage = (event) => {
          // Debug logging for incoming packets
          const data = new Uint8Array(event.data);
          console.log(`[UDPSocketJSI] Incoming packet from ${event.address}:${event.port}, size: ${data.length} bytes`);
          if (data.length > 0) {
            console.log(`[UDPSocketJSI] First byte (service type): 0x${data[0].toString(16).padStart(2, '0')}`);
            if (data[0] === 2) { // Credentials service
              try {
                // @ts-ignore
                const json = new TextDecoder().decode(data.slice(1));
                console.log('[UDPSocketJSI] Credential service payload:', json);
              } catch (e) {
                console.log('[UDPSocketJSI] Failed to decode credential payload');
              }
            }
          }
          handler(event);
        };
        break;
      case 'error':
        this.handlers.onError = handler;
        break;
      case 'close':
        this.handlers.onClose = handler;
        break;
      default:
        throw new Error(`Unknown event: ${event}`);
    }

    // Update native handlers if socket is already created
    if (this.socketId) {
      this.updateEventHandlers();
    }
  }

  /**
   * Close the socket
   */
  async close(): Promise<void> {
    if (!this.socketId) {
      return;
    }

    _udpJSI.close(this.socketId);
    this.socketId = null;
    this.handlers = {};
  }

  private updateEventHandlers(): void {
    if (!this.socketId) {
      return;
    }

    _udpJSI.setEventHandler(this.socketId, this.handlers);
  }
}

/**
 * Utility function to check if JSI bindings are available
 */
export function isJSIAvailable(): boolean {
  return typeof udpSendDirect !== 'undefined' && typeof _udpJSI !== 'undefined';
}

/**
 * Create a UDP socket using JSI bindings
 * 
 * @example
 * ```typescript
 * const socket = await createUDPSocket({ broadcast: true });
 * await socket.bind(12345);
 * 
 * socket.on('message', (event) => {
 *   console.log(`Received from ${event.address}:${event.port}`);
 *   // Zero-copy access to received data
 *   const data = new Uint8Array(event.data);
 *   console.log('Data:', new TextDecoder().decode(data));
 * });
 * 
 * // Zero-copy send
 * const message = new TextEncoder().encode('Hello UDP!');
 * await socket.send(message, 12345, '192.168.1.255');
 * ```
 */
export async function createUDPSocket(options?: UDPSocketOptions): Promise<UDPSocketJSI> {
  const socket = new UDPSocketJSI();
  await socket.create(options);
  return socket;
}