#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface FBExplorationGuard : NSObject
@property(nonatomic,copy,readonly) NSString *fingerprint;
@property(nonatomic,readonly) NSUInteger noEffectCount;
@property(nonatomic,readonly) NSUInteger progressCount;
@property(nonatomic,readonly) NSUInteger blockedCount;
- (nullable NSDictionary *)observeSnapshot:(NSDictionary *)normalized;
- (void)recordAction:(NSDictionary *)action executed:(BOOL)executed reason:(NSString *)reason;
- (NSArray<NSDictionary *> *)exclusionsForCandidates:(NSArray<NSDictionary *> *)candidates;
- (BOOL)hasAvailableActionForCandidates:(NSArray *)candidates canGoBack:(BOOL)canGoBack;
- (BOOL)confirmExhaustion:(BOOL)exhausted atTime:(NSTimeInterval)time;
- (void)clearPending;
@end
NS_ASSUME_NONNULL_END
