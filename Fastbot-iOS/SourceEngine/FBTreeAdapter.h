#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface FBTreeAdapter : NSObject
+ (BOOL)consumeSnapshotNodeAtDepth:(NSUInteger)depth remaining:(NSUInteger *)remaining;
+ (BOOL)isSystemInputContainer:(NSDictionary *)node;
+ (BOOL)inputVisibleForPrunedNode:(NSDictionary *)node viewport:(NSArray *)viewport;
+ (NSDictionary *)pageFromSnapshot:(nullable NSDictionary *)snapshot bundleID:(nullable NSString *)bundleID;
+ (nullable NSDictionary *)targetForAction:(NSDictionary *)action candidates:(NSArray<NSDictionary *> *)candidates;
+ (nullable NSDictionary *)uniqueLiveTargetForCandidates:(NSArray<NSDictionary *> *)candidates lookup:(NSDictionary * (^)(NSDictionary *candidate))lookup;
+ (nullable NSDictionary *)uniqueLiveTargetForCandidates:(NSArray<NSDictionary *> *)candidates lookup:(NSDictionary * (^)(NSDictionary *candidate))lookup diagnostics:(NSMutableDictionary *)diagnostics;
+ (NSPredicate *)livePredicateForTarget:(NSDictionary *)target;
+ (BOOL)target:(NSDictionary *)target matchesLiveBounds:(NSArray<NSNumber *> *)bounds;
@end
NS_ASSUME_NONNULL_END
