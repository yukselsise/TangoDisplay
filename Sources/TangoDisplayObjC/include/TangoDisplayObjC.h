#import <AVFAudio/AVFAudio.h>

/// Calls -[AVAudioEngine connect:to:format:] inside @try/@catch.
/// Returns YES on success. On failure, *outReason is set to the exception reason.
BOOL TDTryAudioEngineConnect(AVAudioEngine *engine,
                              AVAudioNode   *source,
                              AVAudioNode   *destination,
                              AVAudioFormat *format,
                              NSString     **outReason);
BOOL TDTryAudioEngineAttach(AVAudioEngine *engine, AVAudioNode *node, NSString **outReason);
BOOL TDTryAudioEngineDetach(AVAudioEngine *engine, AVAudioNode *node, NSString **outReason);
BOOL TDTryAudioEngineDisconnectOutput(AVAudioEngine *engine, AVAudioNode *node, NSString **outReason);
