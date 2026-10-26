#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface FBExplorationGuard : NSObject
@property(nonatomic,copy,readonly) NSString *fingerprint;
@property(nonatomic,readonly) NSUInteger noEffectCount;
@property(nonatomic,readonly) NSUInteger progressCount;
@property(nonatomic,readonly) NSUInteger blockedCount;
// Rejected selections that neither spend a fresh retry nor eliminate an action.
@property(nonatomic,readonly) NSUInteger stalledRejectionCount;
- (nullable NSDictionary *)observeSnapshot:(NSDictionary *)normalized;
- (void)recordAction:(NSDictionary *)action executed:(BOOL)executed reason:(NSString *)reason;
- (NSArray<NSDictionary *> *)exclusionsForCandidates:(NSArray<NSDictionary *> *)candidates;
- (BOOL)hasAvailableActionForCandidates:(NSArray *)candidates canGoBack:(BOOL)canGoBack;
- (BOOL)confirmExhaustion:(BOOL)exhausted atTime:(NSTimeInterval)time;
- (NSString *)exhaustionContextForCandidates:(NSArray *)candidates canGoBack:(BOOL)canGoBack;
- (BOOL)confirmExhaustion:(BOOL)exhausted atTime:(NSTimeInterval)time context:(NSString *)context;
// Reopen effective routes only after new context discovery and when this context has an exit.
- (NSUInteger)beginNextPassForCandidates:(NSArray *)candidates canGoBack:(BOOL)canGoBack;
// Cancel pending action and exhaustion confirmation before recovery; retain action blocks.
- (void)clearPending;
@end
NS_ASSUME_NONNULL_END
