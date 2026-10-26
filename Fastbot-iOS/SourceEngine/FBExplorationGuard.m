#import "FBExplorationGuard.h"
#import <math.h>
static NSString *s(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSString *digest(NSString *value) {
    uint64_t h = 14695981039346656037ULL;
    NSData *d = [value dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *b = d.bytes;
    for (NSUInteger i = 0; i < d.length; i++) {
        h ^= b[i];
        h *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"%016llx", (unsigned long long)h];
}
static void field(NSMutableString *out, NSString *value) {
    [out appendFormat:@"%lu:%@;", (unsigned long)value.length, value];
}
static void appendTree(id node, NSMutableString *out) {
    if (![node isKindOfClass:NSDictionary.class])
        return;
    [out appendString:@"("];
    NSString *kind = s(node[@"kind"]);
    field(out, kind);
    if (node[@"inputVisible"]) field(out, [node[@"inputVisible"] boolValue] ? @"input-visible" : @"input-hidden");
    field(out, s(node[@"identifier"]));
    BOOL editable = [@[ @"textField", @"secureTextField", @"textView" ] containsObject:kind];
    NSString *label = editable ? @"" : s(node[@"label"]);
    static NSRegularExpression *dynamic, *clock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dynamic = [NSRegularExpression regularExpressionWithPattern:@"^[\\s\\p{N}:.,%+\\-/]+$"
                                                            options:0
                                                              error:nil];
        clock = [NSRegularExpression regularExpressionWithPattern:@"^\\s*\\p{N}{1,2}:\\p{N}{2}(:\\p{N}{2})?\\s*$" options:0 error:nil];
    });
    BOOL nativeAction=[@[@"button",@"cell",@"link",@"switch"] containsObject:kind];
    BOOL clockLabel=label.length && [clock firstMatchInString:label options:0 range:NSMakeRange(0,label.length)];
    if (label.length && (!nativeAction || clockLabel) &&
        [dynamic firstMatchInString:label options:0 range:NSMakeRange(0, label.length)])
        label = @"#dynamic-number";
    field(out, label);
    field(out, [node[@"selected"] boolValue] ? @"selected" : @"unselected");
    field(out, !node[@"enabled"] || [node[@"enabled"] boolValue] ? @"enabled" : @"disabled");
    id frame = node[@"frame"];
    if ([frame isKindOfClass:NSArray.class] && [frame count] == 4) {
        for (id n in frame) {
            double v = [n isKindOfClass:NSNumber.class] ? [n doubleValue] : NAN;
            field(out, isfinite(v) ? [NSString stringWithFormat:@"%.0f", round(v / 2.0)] : @"invalid");
        }
    }
    id children = node[@"children"];
    if ([children isKindOfClass:NSArray.class])
        for (id child in children)
            appendTree(child, out);
    [out appendString:@")"];
}
static NSDictionary *operation(NSDictionary *a) {
    if (![a isKindOfClass:NSDictionary.class])
        return nil;
    NSString *act = s(a[@"act"]);
    if ([act isEqual:@"BACK"])
        return @{@"act" : act};
    if (![@[
            @"CLICK", @"LONG_CLICK", @"SCROLL_TOP_DOWN", @"SCROLL_BOTTOM_UP", @"SCROLL_LEFT_RIGHT",
            @"SCROLL_RIGHT_LEFT", @"SCROLL_BOTTOM_UP_N"
        ] containsObject:act])
        return nil;
    id pos = a[@"pos"];
    if (![pos isKindOfClass:NSArray.class] || [pos count] != 4)
        return nil;
    NSMutableArray *p = [NSMutableArray array];
    for (id n in pos) {
        if (![n isKindOfClass:NSNumber.class] || !isfinite([n doubleValue]))
            return nil;
        [p addObject:@([[NSString stringWithFormat:@"%.0f", [n doubleValue]] longLongValue])];
    }
    if ([p[0] doubleValue] < 0 || [p[1] doubleValue] < 0 || [p[2] doubleValue] <= [p[0] doubleValue] ||
        [p[3] doubleValue] <= [p[1] doubleValue])
        return nil;
    return @{@"act" : act, @"pos" : p};
}
static NSString *operationKey(NSDictionary *a) {
    return [NSString stringWithFormat:@"%@|%@", a[@"act"], a[@"pos"] ?: @[]];
}
@interface FBExplorationGuard ()
@property(nonatomic, copy, readwrite) NSString *fingerprint;
@property(nonatomic, readwrite) NSUInteger noEffectCount, progressCount, blockedCount, stalledRejectionCount;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *blocked;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *noEffects, *transitions;
@property(nonatomic, strong) NSMutableSet<NSString *> *permanentBlocks;
@property(nonatomic, strong) NSMutableSet<NSString *> *seenFingerprints;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *transientRejections;
@property(nonatomic) NSUInteger discoveriesSincePass;
@property(nonatomic, strong) NSDictionary *pending;
@property(nonatomic, copy) NSString *exhaustionFingerprint;
@property(nonatomic) NSTimeInterval exhaustionStarted;
@property(nonatomic) NSUInteger exhaustionChecks;
@end
@implementation FBExplorationGuard
- (instancetype)init {
    if ((self = [super init])) {
        _fingerprint = @"";
        _blocked = [NSMutableDictionary dictionary];
        _noEffects = [NSMutableDictionary dictionary];
        _transitions = [NSMutableDictionary dictionary];
        _permanentBlocks = [NSMutableSet set];
        _seenFingerprints = [NSMutableSet set];
        _transientRejections = [NSMutableDictionary dictionary];
    }
    return self;
}
- (NSString *)keyFor:(NSDictionary *)a fingerprint:(NSString *)fp {
    return [NSString stringWithFormat:@"%@|%@", fp, operationKey(a)];
}
- (void)block:(NSDictionary *)a fingerprint:(NSString *)fp {
    NSMutableDictionary *page = self.blocked[fp];
    if (!page) {
        page = [NSMutableDictionary dictionary];
        self.blocked[fp] = page;
    }
    NSString *key = operationKey(a);
    if (!page[key]) {
        page[key] = a;
        self.blockedCount++;
    }
}
- (NSDictionary *)observeSnapshot:(NSDictionary *)normalized {
    NSMutableString *tree = [NSMutableString string];
    appendTree(normalized, tree);
    self.fingerprint = digest(tree);
    if (![self.seenFingerprints containsObject:self.fingerprint]) {
        [self.seenFingerprints addObject:self.fingerprint];
        self.discoveriesSincePass++;
    }
    NSDictionary *pending = self.pending;
    self.pending = nil;
    if (!pending)
        return nil;
    NSDictionary *a = pending[@"action"];
    NSString *before = pending[@"before"], *pair = [self keyFor:a fingerprint:before];
    BOOL changed = ![before isEqual:self.fingerprint];
    BOOL block = NO;
    if (changed) {
        [self.noEffects removeObjectForKey:pair];
        self.progressCount++;
        NSString *transition = [pair stringByAppendingFormat:@"|%@", self.fingerprint];
        NSUInteger count = [self.transitions[transition] unsignedIntegerValue] + 1;
        self.transitions[transition] = @(count);
        block = count >= 2;
    } else {
        self.noEffectCount++;
        NSUInteger count = [self.noEffects[pair] unsignedIntegerValue] + 1;
        self.noEffects[pair] = @(count);
        block = count >= 2;
        if (block) [self.permanentBlocks addObject:pair];
    }
    if (block)
        [self block:a fingerprint:before];
    return @{
        @"kind" : @"action_effect",
        @"act" : a[@"act"],
        @"effect" : changed ? @"changed" : @"no_observable_change",
        @"blocked" : @(self.blocked[before][operationKey(a)] != nil),
        @"beforeFingerprint" : before,
        @"afterFingerprint" : self.fingerprint
    };
}
- (NSString *)exhaustionContextForCandidates:(NSArray *)candidates canGoBack:(BOOL)canGoBack {
    NSMutableSet *keys=[NSMutableSet set];
    for (NSDictionary *action in [self availableOperations:candidates]) [keys addObject:operationKey(action)];
    if (canGoBack) [keys addObject:operationKey(@{@"act":@"BACK"})];
    NSMutableString *context=[NSMutableString string];
    field(context,self.fingerprint);
    for (NSString *key in [[keys allObjects] sortedArrayUsingSelector:@selector(compare:)]) field(context,key);
    return digest(context);
}
- (BOOL)confirmExhaustion:(BOOL)exhausted atTime:(NSTimeInterval)time {
    return [self confirmExhaustion:exhausted atTime:time context:self.fingerprint];
}
- (BOOL)confirmExhaustion:(BOOL)exhausted atTime:(NSTimeInterval)time context:(NSString *)context {
    if (!exhausted) {
        self.exhaustionFingerprint = nil;
        self.exhaustionChecks = 0;
        return NO;
    }
    if (![self.exhaustionFingerprint isEqualToString:context]) {
        self.exhaustionFingerprint = context;
        self.exhaustionStarted = time;
        self.exhaustionChecks = 1;
        return NO;
    }
    return ++self.exhaustionChecks >= 3 && time - self.exhaustionStarted >= 2;
}
- (void)recordAction:(NSDictionary *)action executed:(BOOL)executed reason:(NSString *)reason {
    self.pending = nil;
    self.stalledRejectionCount = executed ? 0 : self.stalledRejectionCount + 1;
    NSDictionary *a = operation(action);
    if (!a)
        return;
    NSString *pair = [self keyFor:a fingerprint:self.fingerprint];
    if (executed) {
        [self.transientRejections removeObjectForKey:pair];
        self.pending = @{@"action" : a, @"before" : self.fingerprint};
    } else {
        // A rejected unblocked operation spends a finite attempt or removes a
        // candidate. Only repeated blocked/unsupported selections are a stall.
        if (self.blocked[self.fingerprint][operationKey(a)]) return;
        self.stalledRejectionCount = 0;
        if ([reason isEqual:@"target_stale_or_not_hittable"]) {
            NSUInteger failures = [self.transientRejections[pair] unsignedIntegerValue] + 1;
            self.transientRejections[pair] = @(failures);
            if (failures < 2) return;
        }
        [self.permanentBlocks addObject:[self keyFor:a fingerprint:self.fingerprint]];
        [self block:a fingerprint:self.fingerprint];
    }
}
- (NSArray *)availableOperations:(NSArray *)candidates {
    NSMutableArray *ops = [NSMutableArray array];
    for (id c in candidates) {
        if (![c isKindOfClass:NSDictionary.class])
            continue;
        NSMutableArray *directions = [NSMutableArray array];
        if ([c[@"scrollable"] boolValue]) {
            id declared = c[@"scrollDirections"];
            NSArray *requested = [declared isKindOfClass:NSArray.class]
                                     ? declared
                                     : @[ @"SCROLL_TOP_DOWN", @"SCROLL_BOTTOM_UP" ];
            for (id direction in requested)
                if ([@[ @"SCROLL_TOP_DOWN", @"SCROLL_BOTTOM_UP", @"SCROLL_LEFT_RIGHT", @"SCROLL_RIGHT_LEFT" ]
                        containsObject:direction])
                    [directions addObject:direction];
        }
        NSArray *acts = directions;
        if ([c[@"clickable"] boolValue])
            acts = [acts arrayByAddingObject:@"CLICK"];
        for (NSString *act in acts) {
            NSDictionary *a = operation(@{@"act" : act, @"pos" : c[@"bounds"] ?: @[]});
            if (a)
                [ops addObject:a];
        }
    }
    return ops;
}
- (NSArray<NSDictionary *> *)exclusionsForCandidates:(NSArray<NSDictionary *> *)candidates {
    NSDictionary *page = self.blocked[self.fingerprint];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *key in [[page allKeys] sortedArrayUsingSelector:@selector(compare:)])
        [out addObject:page[key]];
    // XML class controls the core action pool; enforce the declared native axes
    // again here so unsupported directions cannot consume real gestures.
    NSMutableSet *keys = [NSMutableSet set];
    for (NSDictionary *entry in out) [keys addObject:operationKey(entry)];
    for (NSDictionary *candidate in candidates) {
        if (![candidate[@"scrollable"] boolValue] ||
            ![candidate[@"scrollDirections"] isKindOfClass:NSArray.class]) continue;
        for (NSString *direction in @[@"SCROLL_TOP_DOWN",@"SCROLL_BOTTOM_UP",@"SCROLL_LEFT_RIGHT",@"SCROLL_RIGHT_LEFT"]) {
            if ([candidate[@"scrollDirections"] containsObject:direction]) continue;
            NSDictionary *entry=operation(@{@"act":direction,@"pos":candidate[@"bounds"] ?: @[]});
            if (entry && ![keys containsObject:operationKey(entry)]) {
                [out addObject:entry]; [keys addObject:operationKey(entry)];
            }
        }
    }
    return out;
}
- (BOOL)hasAvailableActionForCandidates:(NSArray *)candidates canGoBack:(BOOL)canGoBack {
    NSMutableArray *ops = [[self availableOperations:candidates] mutableCopy];
    if (canGoBack)
        [ops addObject:@{@"act" : @"BACK"}];
    for (NSDictionary *a in ops)
        if (!self.blocked[self.fingerprint][operationKey(a)])
            return YES;
    return NO;
}
- (NSUInteger)beginNextPassForCandidates:(NSArray *)candidates canGoBack:(BOOL)canGoBack {
    if (!self.discoveriesSincePass) return 0;
    BOOL currentExit = NO;
    NSMutableArray *current=[[self availableOperations:candidates] mutableCopy];
    if (canGoBack) [current addObject:@{@"act":@"BACK"}];
    for (NSDictionary *action in current)
        if (self.blocked[self.fingerprint][operationKey(action)] &&
            ![self.permanentBlocks containsObject:[self keyFor:action fingerprint:self.fingerprint]]) currentExit = YES;
    if (!currentExit) return 0; // Reopening another page cannot escape this context.
    NSUInteger reopened = 0;
    for (NSString *fp in self.blocked.allKeys) {
        NSMutableDictionary *page = self.blocked[fp];
        for (NSString *key in page.allKeys) {
            if (![self.permanentBlocks containsObject:[self keyFor:page[key] fingerprint:fp]]) {
                [page removeObjectForKey:key];
                reopened++;
            }
        }
    }
    if (reopened) {
        self.discoveriesSincePass = 0;
        [self.transitions removeAllObjects];
        [self confirmExhaustion:NO atTime:0];
    }
    return reopened;
}
- (void)clearPending {
    self.pending = nil;
    self.stalledRejectionCount = 0;
    // Recovery starts a fresh observation window even when launch returns to
    // exactly the same tree. Keep action blocks to avoid replaying dead ends.
    [self confirmExhaustion:NO atTime:0];
}
@end
