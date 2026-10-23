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
    field(out, s(node[@"identifier"]));
    BOOL editable = [@[ @"textField", @"secureTextField", @"textView" ] containsObject:kind];
    NSString *label = editable ? @"" : s(node[@"label"]);
    static NSRegularExpression *dynamic;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dynamic = [NSRegularExpression regularExpressionWithPattern:@"^[\\s\\p{N}:.,%+\\-/]+$"
                                                            options:0
                                                              error:nil];
    });
    if (label.length && [dynamic firstMatchInString:label options:0 range:NSMakeRange(0, label.length)])
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
@property(nonatomic, readwrite) NSUInteger noEffectCount, progressCount, blockedCount;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *blocked;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *noEffects, *transitions;
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
    NSDictionary *pending = self.pending;
    self.pending = nil;
    if (!pending)
        return nil;
    NSDictionary *a = pending[@"action"];
    NSString *before = pending[@"before"], *pair = [self keyFor:a fingerprint:before];
    BOOL changed = ![before isEqual:self.fingerprint];
    BOOL block = NO;
    if (changed) {
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
- (BOOL)confirmExhaustion:(BOOL)exhausted atTime:(NSTimeInterval)time {
    if (!exhausted) {
        self.exhaustionFingerprint = nil;
        self.exhaustionChecks = 0;
        return NO;
    }
    if (![self.exhaustionFingerprint isEqualToString:self.fingerprint]) {
        self.exhaustionFingerprint = self.fingerprint;
        self.exhaustionStarted = time;
        self.exhaustionChecks = 1;
        return NO;
    }
    return ++self.exhaustionChecks >= 3 && time - self.exhaustionStarted >= 2;
}
- (void)recordAction:(NSDictionary *)action executed:(BOOL)executed reason:(NSString *)reason {
    self.pending = nil;
    NSDictionary *a = operation(action);
    if (!a)
        return;
    if (executed)
        self.pending = @{@"action" : a, @"before" : self.fingerprint};
    else
        [self block:a fingerprint:self.fingerprint];
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
- (void)clearPending {
    self.pending = nil;
}
@end
