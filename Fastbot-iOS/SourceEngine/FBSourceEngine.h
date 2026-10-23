#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Internal-use, source-built ModelReusableAgent. Snapshot keys describe accessibility states.
@interface FBSourceEngine : NSObject
- (nullable instancetype)initWithStorageDirectory:(NSString *)directory bundleID:(NSString *)bundleID seed:(unsigned int)seed;
- (nullable NSDictionary *)nextActionForXML:(NSString *)xml pageKey:(NSString *)pageKey error:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary *)nextActionForXML:(NSString *)xml pageKey:(NSString *)pageKey excludingActions:(NSArray<NSDictionary *> *)excluded error:(NSError * _Nullable * _Nullable)error;
@property(nonatomic, readonly) NSUInteger stateCount;
- (void)close;
@end
NS_ASSUME_NONNULL_END
