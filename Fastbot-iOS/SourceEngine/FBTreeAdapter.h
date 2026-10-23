#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface FBTreeAdapter : NSObject
+ (BOOL)isSystemInputContainer:(NSDictionary *)node;
+ (NSDictionary *)pageFromSnapshot:(nullable NSDictionary *)snapshot bundleID:(nullable NSString *)bundleID;
+ (nullable NSDictionary *)targetForAction:(NSDictionary *)action candidates:(NSArray<NSDictionary *> *)candidates;
+ (BOOL)target:(NSDictionary *)target matchesLiveBounds:(NSArray<NSNumber *> *)bounds;
@end
NS_ASSUME_NONNULL_END
