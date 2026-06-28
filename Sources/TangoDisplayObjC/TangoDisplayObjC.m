#import "include/TangoDisplayObjC.h"

BOOL TDTryAudioEngineConnect(AVAudioEngine *engine,
                              AVAudioNode   *source,
                              AVAudioNode   *destination,
                              AVAudioFormat *format,
                              NSString     **outReason) {
    @try {
        [engine connect:source to:destination format:format];
        return YES;
    } @catch (NSException *ex) {
        if (outReason) *outReason = ex.reason ?: ex.name;
        return NO;
    }
}

BOOL TDTryAudioEngineAttach(AVAudioEngine *engine, AVAudioNode *node, NSString **outReason) {
    @try { [engine attachNode:node]; return YES; }
    @catch (NSException *ex) { if (outReason) *outReason = ex.reason ?: ex.name; return NO; }
}

BOOL TDTryAudioEngineDetach(AVAudioEngine *engine, AVAudioNode *node, NSString **outReason) {
    @try { [engine detachNode:node]; return YES; }
    @catch (NSException *ex) { if (outReason) *outReason = ex.reason ?: ex.name; return NO; }
}

BOOL TDTryAudioEngineDisconnectOutput(AVAudioEngine *engine, AVAudioNode *node, NSString **outReason) {
    @try { [engine disconnectNodeOutput:node]; return YES; }
    @catch (NSException *ex) { if (outReason) *outReason = ex.reason ?: ex.name; return NO; }
}
