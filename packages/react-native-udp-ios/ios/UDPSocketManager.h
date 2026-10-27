#import <Foundation/Foundation.h>
#import "GCDAsyncUdpSocket.h" // Import GCDAsyncUdpSocket
#import "UDPErrorCodes.h"   // For error constants

NS_ASSUME_NONNULL_BEGIN

// Forward declaration for the C++ owner (optional, can use void*)
// class UDPDirectModuleCxxImpl;

// Callback Types
typedef void (^UDPSocketDidReceiveData)(NSNumber* socketId, NSData* data, NSString* host, uint16_t port, NSNumber* bufferId);
typedef void (^UDPSocketDidClose)(NSNumber* socketId, NSError* _Nullable error);
typedef void (^UDPSocketDidSendData)(NSNumber* socketId, long tag);
typedef void (^UDPSocketDidNotSendData)(NSNumber* socketId, long tag, NSError* error);

@interface UDPSocketManager : NSObject <GCDAsyncUdpSocketDelegate>

// Properties for callbacks to the C++ owner
@property (nonatomic, copy, nullable) UDPSocketDidReceiveData onDataReceived;
@property (nonatomic, copy, nullable) UDPSocketDidClose onSocketClosed;
@property (nonatomic, copy, nullable) UDPSocketDidSendData onSendSuccess;
@property (nonatomic, copy, nullable) UDPSocketDidNotSendData onSendFailure;

// --- Buffer Management ---
// We need a simplified buffer management system here, or the C++ layer handles it.
// For now, let's assume this manager also handles the receive buffers.
@property (nonatomic, strong, readonly) NSMutableDictionary<NSNumber*, NSMutableData*> *buffers;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSNumber*, NSNumber*> *bufferStatus; // e.g., readyForJS, inUseByJS
@property (nonatomic, assign) NSInteger nextBufferId;


- (instancetype)initWithDelegateQueue:(dispatch_queue_t)queue;

// Socket Operations
- (nullable NSNumber *)createSocketWithOptions:(NSDictionary *)options error:(NSError **)error;
- (BOOL)bindSocket:(NSNumber *)socketId toPort:(uint16_t)port address:(nullable NSString *)address error:(NSError **)error;
- (void)sendData:(NSData *)data onSocket:(NSNumber *)socketId toHost:(NSString *)host port:(uint16_t)port tag:(long)tag;
- (void)sendDataFromBuffer:(NSNumber *)bufferId offset:(NSUInteger)offset length:(NSUInteger)length onSocket:(NSNumber *)socketId toHost:(NSString *)host port:(uint16_t)port tag:(long)tag;

- (void)closeSocket:(NSNumber *)socketId;
- (void)closeAllSockets;
- (void)closeAllSocketsSynchronously; // Synchronous version for cleanup during app reload
- (void)startReceivingOnBoundSockets;

// Expose delegate queue for cleanup coordination
@property (nonatomic, readonly) dispatch_queue_t delegateQueue;

// Expose internal socket dictionaries for port management (readonly access)
@property (nonatomic, strong, readonly) NSDictionary<NSNumber*, GCDAsyncUdpSocket*> *asyncSockets;
@property (nonatomic, strong, readonly) NSDictionary<NSNumber*, NSNumber*> *socketStatus;

// Socket Options
- (BOOL)setBroadcast:(NSNumber *)socketId enable:(BOOL)enable error:(NSError **)error;
- (BOOL)setTTL:(NSNumber *)socketId ttl:(int)ttl error:(NSError **)error; // Changed to int for setsockopt
- (BOOL)setMulticastTTL:(NSNumber *)socketId ttl:(int)ttl error:(NSError **)error; // Changed to int
- (BOOL)setMulticastLoopback:(NSNumber *)socketId flag:(BOOL)flag error:(NSError **)error;
- (BOOL)joinMulticastGroup:(NSNumber *)socketId address:(NSString *)address error:(NSError **)error;
- (BOOL)leaveMulticastGroup:(NSNumber *)socketId address:(NSString *)address error:(NSError **)error;

// Utility
- (nullable NSDictionary *)getSocketAddress:(NSNumber *)socketId;
- (NSArray<NSString *> *)getLocalIPAddresses;

// Buffer Management methods called by C++
- (nullable NSNumber *)createManagedBufferOfSize:(NSUInteger)size;
- (void)releaseManagedBuffer:(NSNumber *)bufferIdFromJS; // Called when JS is done, might not immediately dealloc if native still uses it
- (nullable NSMutableData *)getModifiableBufferWithId:(NSNumber *)bufferId;
- (void)jsDidAcquireReceivedBuffer:(NSNumber *)bufferId; // Transitions buffer to "inUseByJS"
- (void)jsDidReleaseBufferId:(NSNumber *)bufferId; // JSI finalizer for a *received* data buffer

- (nullable NSDictionary *)getDiagnostics;

@end

NS_ASSUME_NONNULL_END 