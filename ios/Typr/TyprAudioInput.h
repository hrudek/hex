#import <AVFAudio/AVFAudio.h>

NS_ASSUME_NONNULL_BEGIN

/// Owns the input graph and contains AVFAudio's Objective-C exceptions. No Swift
/// code runs inside the exception boundary (apart from the later audio callback).
@interface TyprAudioInput : NSObject
@property(nonatomic, readonly, getter=isRunning) BOOL running;
- (instancetype)init;
/// Injection for graph-lifecycle regression tests; production uses init.
- (instancetype)initWithEngineFactory:(AVAudioEngine * (^)(void))engineFactory;
- (BOOL)startWithBufferHandler:(AVAudioNodeTapBlock)handler
                       error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(start(bufferHandler:));
- (void)stop;
@end

NS_ASSUME_NONNULL_END
