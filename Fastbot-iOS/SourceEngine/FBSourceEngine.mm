#import "FBSourceEngine.h"
#include "core/PortableEngine.h"
#include <memory>
#include <stdexcept>
@implementation FBSourceEngine {
    std::unique_ptr<fastbot_ios::PortableEngine> _engine;
}
- (instancetype)initWithStorageDirectory:(NSString *)directory bundleID:(NSString *)bundleID seed:(unsigned int)seed {
    self = [super init];
    if (self) {
        NSError *error = nil;
        if (!directory.isAbsolutePath || ![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) return nil;
        try { _engine.reset(new fastbot_ios::PortableEngine(directory.UTF8String, bundleID.UTF8String, seed)); }
        catch (const std::exception &) { return nil; }
    }
    return self;
}
- (NSDictionary *)nextActionForXML:(NSString *)xml pageKey:(NSString *)pageKey error:(NSError **)error {
    return [self nextActionForXML:xml pageKey:pageKey excludingActions:@[] error:error];
}
- (NSDictionary *)nextActionForXML:(NSString *)xml pageKey:(NSString *)pageKey excludingActions:(NSArray<NSDictionary *> *)excluded error:(NSError **)error {
    @synchronized(self) {
        try {
            if (!_engine) throw std::runtime_error("engine is closed");
            NSData *xmlData = [xml dataUsingEncoding:NSUTF8StringEncoding];
            std::string input(static_cast<const char *>(xmlData.bytes), xmlData.length);
            NSData *exclusionData = [NSJSONSerialization dataWithJSONObject:excluded ?: @[] options:0 error:error];
            if (!exclusionData) return nil;
            std::string exclusionJSON(static_cast<const char *>(exclusionData.bytes), exclusionData.length);
            std::string result = _engine->next(input, pageKey.UTF8String ?: "", exclusionJSON);
            NSData *data = [NSData dataWithBytes:result.data() length:result.size()];
            return [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
        } catch (const std::exception &exception) {
            if (error) *error = [NSError errorWithDomain:@"FBSourceEngine" code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:exception.what()] ?: @"Source engine failed"}];
            return nil;
        }
    }
}
- (NSUInteger)stateCount { @synchronized(self) { return _engine ? _engine->stateCount() : 0; } }
- (void)close { @synchronized(self) { if (_engine) { _engine->close(); _engine.reset(); } } }
- (void)dealloc { [self close]; }
@end
