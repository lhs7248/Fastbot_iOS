#import "FBTreeAdapter.h"
#import <math.h>
static NSString *str(id x) { return [x isKindOfClass:NSString.class] ? x : @""; }
static NSString *escape(NSString *s) {
    for (NSArray *p in @[
             @[ @"&", @"&amp;" ], @[ @"<", @"&lt;" ], @[ @">", @"&gt;" ], @[ @"\"", @"&quot;" ],
             @[ @"'", @"&apos;" ]
         ])
        s = [s stringByReplacingOccurrencesOfString:p[0] withString:p[1]];
    NSMutableString *safe = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= 32 || c == 9 || c == 10 || c == 13)
            [safe appendFormat:@"%C", c];
    }
    return safe;
}
static BOOL numbers(id a) {
    if (![a isKindOfClass:NSArray.class] || [a count] != 4)
        return NO;
    for (id n in a)
        if (![n isKindOfClass:NSNumber.class] || !isfinite([n doubleValue]))
            return NO;
    return YES;
}
static NSString *klass(NSString *k) {
    NSDictionary *m = @{
        @"button" : @"Button",
        @"cell" : @"Button",
        @"link" : @"Button",
        @"switch" : @"Switch",
        @"textField" : @"EditText",
        @"secureTextField" : @"EditText",
        @"textView" : @"EditText",
        @"scrollView" : @"ScrollView",
        @"table" : @"ScrollView",
        @"collectionView" : @"ScrollView",
        @"webView" : @"WebView",
        @"staticText" : @"TextView"
    };
    return [@"android.widget." stringByAppendingString:m[k] ?: @"FrameLayout"];
}
// This is a candidate heuristic, not proof of an accessibility action trait.
static BOOL inferredLabelTarget(NSString *kind, NSString *label, double w, double h, double screenWidth) {
    if (![@[@"other", @"staticText"] containsObject:kind] || !label.length || label.length > 80 ||
        [label rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound)
        return NO;
    NSString *lower = label.lowercaseString;
    if ([lower containsString:@"滚动条"] || [lower containsString:@"scroll bar"] ||
        [lower containsString:@"scrollbar"])
        return NO;
    return w >= 8 && h >= 8 && h <= 88 && w <= screenWidth;
}
static BOOL pageCounter(NSString *label) {
    return [label rangeOfString:@"^\\s*[0-9]+\\s*/\\s*[0-9]+\\s*$"
                       options:NSRegularExpressionSearch].location != NSNotFound;
}
static BOOL containsCounter(NSDictionary *node) {
    if (![node isKindOfClass:NSDictionary.class]) return NO;
    if (pageCounter(str(node[@"label"]))) return YES;
    for (NSDictionary *child in node[@"children"])
        if (containsCounter(child)) return YES;
    return NO;
}
static BOOL headerBack(NSDictionary *node, NSArray *siblings, NSArray *screen) {
    if (![str(node[@"kind"]) isEqual:@"other"] || str(node[@"label"]).length ||
        !numbers(node[@"frame"]) || !numbers(screen)) return NO;
    NSArray *f = node[@"frame"];
    double x=[f[0] doubleValue], y=[f[1] doubleValue], w=[f[2] doubleValue], h=[f[3] doubleValue];
    if (x < 0 || x > 24 || y < 20 || y > 100 || w < 28 || w > 60 || h < 28 || h > 60) return NO;
    for (NSDictionary *sibling in siblings) {
        if (![str(sibling[@"kind"]) isEqual:@"staticText"] || !str(sibling[@"label"]).length ||
            !numbers(sibling[@"frame"])) continue;
        NSArray *t=sibling[@"frame"];
        double center=[t[0] doubleValue]+[t[2] doubleValue]/2;
        if (fabs(center-([screen[0] doubleValue]+[screen[2] doubleValue])/2) < 24 &&
            fabs([t[1] doubleValue]+[t[3] doubleValue]/2-y-h/2) < 20) return YES;
    }
    return NO;
}
static BOOL nativeClickDescendant(NSDictionary *node, NSArray *frame) {
    for (NSDictionary *child in node[@"children"]) {
        if (![child isKindOfClass:NSDictionary.class] || (child[@"enabled"] && ![child[@"enabled"] boolValue])) continue;
        NSString *kind=str(child[@"kind"]);
        BOOL native=[@[@"button",@"cell",@"link",@"switch",@"textField",@"secureTextField",@"textView"] containsObject:kind];
        if (native && numbers(child[@"frame"])) {
            BOOL same=YES;
            for (NSUInteger i=0;i<4;i++) if (fabs([frame[i] doubleValue]-[child[@"frame"][i] doubleValue])>0.5) same=NO;
            if (same) return YES;
        }
        if (nativeClickDescendant(child,frame)) return YES;
    }
    return NO;
}
static NSString *liveKey(NSDictionary *n, NSString *label) {
    return [NSString stringWithFormat:@"%@|%@|%@|%@", n[@"type"] ?: @0,
            str(n[@"identifier"]), label, n[@"frame"] ?: @[]];
}
static void walk(NSDictionary *n, NSString *path, NSArray *screen, NSString *bundle, NSMutableString *xml,
                 NSMutableString *structure, NSMutableArray *candidates, NSUInteger *count,
                 BOOL ancestorEnabled, NSMutableDictionary *clickRegions, NSMutableDictionary *liveCounts, BOOL isHeaderBack, BOOL insideWeb, NSMutableSet *scrollRegions) {
    if (![n isKindOfClass:NSDictionary.class] || [FBTreeAdapter isSystemInputContainer:n])
        return;
    (*count)++;
    NSString *kind = str(n[@"kind"]), *ident = str(n[@"identifier"]);
    BOOL secure = [kind isEqual:@"secureTextField"];
    BOOL enabled = ancestorEnabled && ![@[@"keyboard", @"statusBar"] containsObject:kind] &&
                   (!n[@"enabled"] || [n[@"enabled"] boolValue]);
    BOOL editable = [@[ @"textField", @"textView", @"secureTextField" ] containsObject:kind];
    BOOL scroll = [@[ @"scrollView", @"table", @"collectionView", @"webView" ] containsObject:kind];
    BOOL click = editable || [@[ @"button", @"cell", @"link", @"switch" ] containsObject:kind];
    double l = 0, t = 0, r = 0, b = 0;
    BOOL valid = numbers(n[@"frame"]) && numbers(screen);
    if (valid) {
        NSArray *f = n[@"frame"];
        double x = [f[0] doubleValue], y = [f[1] doubleValue], w = [f[2] doubleValue], h = [f[3] doubleValue];
        l = fmax(x, [screen[0] doubleValue]);
        t = fmax(y, [screen[1] doubleValue]);
        r = fmin(x + w, [screen[2] doubleValue]);
        b = fmin(y + h, [screen[3] doubleValue]);
        valid = w > 0 && h > 0 && r > l && b > t;
    }
    if (!valid) {
        l = 0;
        t = 0;
        r = 0;
        b = 0;
    }
    NSString *label = secure ? @"" : str(n[@"label"]);
    BOOL inferred = !insideWeb && !click && !pageCounter(label) && valid && inferredLabelTarget(kind, label, [n[@"frame"][2] doubleValue],
                                                          [n[@"frame"][3] doubleValue],
                                                          [screen[2] doubleValue]-[screen[0] doubleValue]);
    if (valid && (inferred || isHeaderBack) && nativeClickDescendant(n,n[@"frame"])) {
        inferred = NO;
        isHeaderBack = NO;
    }
    click = (click || inferred || isHeaderBack) && enabled && valid;
    NSString *liveIdentity = liveKey(n, label);
    if (enabled && valid)
        liveCounts[liveIdentity] = @([liveCounts[liveIdentity] unsignedIntegerValue] + 1);
    NSString *region = [NSString stringWithFormat:@"%.0f,%.0f,%.0f,%.0f", l,t,r,b];
    NSMutableSet *regionIdentities=clickRegions[region];
    if (click && [regionIdentities containsObject:liveIdentity]) click=NO;
    if (click) {
        if (!regionIdentities) { regionIdentities=[NSMutableSet set];clickRegions[region]=regionIdentities; }
        [regionIdentities addObject:liveIdentity];
    }
    scroll = scroll && enabled && valid && ![scrollRegions containsObject:region];
    if (scroll) [scrollRegions addObject:region];
    BOOL horizontal=scroll && ![kind isEqualToString:@"webView"] &&
        [n[@"frame"][3] doubleValue] <= 96 && [n[@"frame"][2] doubleValue] > [n[@"frame"][3] doubleValue]*3;
    NSArray *bounds = @[ @(l), @(t), @(r), @(b) ];
    [structure
        appendFormat:@"(%lu:%@|%lu:%@", (unsigned long)kind.length, kind, (unsigned long)ident.length, ident];
    [xml appendFormat:
             @"<node index=\"%@\" text=\"%@\" resource-id=\"%@\" class=\"%@\" package=\"%@\" "
             @"content-desc=\"%@\" enabled=\"%@\" clickable=\"%@\" scrollable=\"%@\" "
             @"long-clickable=\"false\" selected=\"%@\" password=\"%@\" bounds=\"[%.0f,%.0f][%.0f,%.0f]\">",
             escape(path), escape(editable ? @"" : label), escape(ident), horizontal ? @"android.widget.HorizontalScrollView" : klass(kind), escape(bundle),
             escape(label), enabled ? @"true" : @"false", click ? @"true" : @"false",
             scroll ? @"true" : @"false", [n[@"selected"] boolValue] ? @"true" : @"false",
             secure ? @"true" : @"false", l, t, r, b];
    if (click || scroll)
        [candidates addObject:@{
            @"identifier" : ident,
            @"liveIdentity" : liveIdentity,
            @"recognition" : isHeaderBack ? @"inferred_header_back" : inferred ? @"inferred_label" : @"native_role",
            @"nativePath" : n[@"nativePath"] ?: @[],
            @"label" : label,
            @"type" : [n[@"type"] isKindOfClass:NSNumber.class] ? n[@"type"] : @0,
            @"bounds" : bounds,
            @"originalBounds" : @[
                @([n[@"frame"][0] doubleValue]), @([n[@"frame"][1] doubleValue]),
                @([n[@"frame"][0] doubleValue] + [n[@"frame"][2] doubleValue]),
                @([n[@"frame"][1] doubleValue] + [n[@"frame"][3] doubleValue])
            ],
            @"path" : path,
            @"editable" : @(editable && !secure),
            @"secure" : @(secure),
            @"scrollable" : @(scroll),
            @"scrollDirections" : horizontal
                ? @[ @"SCROLL_LEFT_RIGHT", @"SCROLL_RIGHT_LEFT" ]
                : [kind isEqualToString:@"webView"]
                ? @[ @"SCROLL_TOP_DOWN", @"SCROLL_BOTTOM_UP", @"SCROLL_LEFT_RIGHT", @"SCROLL_RIGHT_LEFT" ]
                : @[ @"SCROLL_TOP_DOWN", @"SCROLL_BOTTOM_UP" ],
            @"clickable" : @(click)
        }];
    id children = n[@"children"];
    if ([children isKindOfClass:NSArray.class]) {
        NSUInteger i = 0;
        for (id child in children) {
            walk(child, [path stringByAppendingFormat:@"/%lu", (unsigned long)i++], screen, bundle, xml,
                 structure, candidates, count, enabled, clickRegions, liveCounts, headerBack(child, children, screen), insideWeb || [kind isEqual:@"webView"], scrollRegions);
        }
    }
    [xml appendString:@"</node>"];
    [structure appendString:@")"];
}
@implementation FBTreeAdapter
+ (BOOL)consumeSnapshotNodeAtDepth:(NSUInteger)depth remaining:(NSUInteger *)remaining {
    if (depth>60) { *remaining=0; return NO; }
    if (*remaining==0) return NO;
    --*remaining;
    return YES;
}
+ (BOOL)inputVisibleForPrunedNode:(NSDictionary *)node viewport:(NSArray *)viewport {
    if (![node isKindOfClass:NSDictionary.class] || !numbers(viewport)) return NO;
    NSString *kind=str(node[@"kind"]);
    BOOL input=[@[@"keyboard",@"key"] containsObject:kind] ||
        [str(node[@"identifier"]) isEqual:@"SystemInputAssistantView"];
    if (!input) {
        for (NSDictionary *child in node[@"children"])
            if ([child isKindOfClass:NSDictionary.class] &&
                [str(child[@"identifier"]) isEqual:@"SystemInputAssistantView"] &&
                [self inputVisibleForPrunedNode:child viewport:viewport]) return YES;
        return NO;
    }
    NSArray *f=node[@"frame"];
    if (!numbers(f) || [f[2] doubleValue]<=0 || [f[3] doubleValue]<=0 ||
        [viewport[2] doubleValue]<=0 || [viewport[3] doubleValue]<=0) return NO;
    return fmin([f[0] doubleValue]+[f[2] doubleValue], [viewport[0] doubleValue]+[viewport[2] doubleValue]) >
               fmax([f[0] doubleValue], [viewport[0] doubleValue]) &&
           fmin([f[1] doubleValue]+[f[3] doubleValue], [viewport[1] doubleValue]+[viewport[3] doubleValue]) >
               fmax([f[1] doubleValue], [viewport[1] doubleValue]);
}
+ (BOOL)isSystemInputContainer:(NSDictionary *)node {
    if ([@[@"keyboard", @"key", @"statusBar"] containsObject:str(node[@"kind"])] ||
        [str(node[@"identifier"]) isEqualToString:@"SystemInputAssistantView"])
        return YES;
    // On iOS 26, suggestions and the emoji inputView are siblings under this
    // system host. Removing only the Keyboard role leaves these native Cells.
    id children = node[@"children"];
    if ([children isKindOfClass:NSArray.class])
        for (id child in children)
            if ([child isKindOfClass:NSDictionary.class] &&
                [str(child[@"identifier"]) isEqualToString:@"SystemInputAssistantView"])
                return YES;
    return NO;
}
+ (NSDictionary *)pageFromSnapshot:(NSDictionary *)snapshot bundleID:(NSString *)bundleID {
    NSMutableString
        *xml = [NSMutableString
            stringWithString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?><hierarchy rotation=\"0\">"],
        *structure = [NSMutableString stringWithString:str(bundleID)];
    NSMutableArray *candidates = [NSMutableArray array];
    NSUInteger count = 0;
    NSArray *screen = nil;
    if ([snapshot isKindOfClass:NSDictionary.class] && numbers(snapshot[@"frame"])) {
        NSArray *f = snapshot[@"frame"];
        double x = [f[0] doubleValue], y = [f[1] doubleValue], w = [f[2] doubleValue], h = [f[3] doubleValue];
        if (w > 0 && h > 0)
            screen = @[ @(x), @(y), @(x + w), @(y + h) ];
    }
    NSMutableDictionary *liveCounts = [NSMutableDictionary dictionary];
    walk(snapshot, @"0", screen, str(bundleID), xml, structure, candidates, &count, YES,
         [NSMutableDictionary dictionary], liveCounts, NO, NO, [NSMutableSet set]);
    for (NSUInteger i=0; i<candidates.count; i++) {
        NSMutableDictionary *candidate = [candidates[i] mutableCopy];
        candidate[@"liveMatchCount"] = liveCounts[candidate[@"liveIdentity"]] ?: @1;
        [candidate removeObjectForKey:@"liveIdentity"];
        candidates[i] = candidate;
    }
    [xml appendString:@"</hierarchy>"];
    uint64_t hash = 14695981039346656037ULL;
    NSData *data = [structure dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        hash ^= bytes[i];
        hash *= 1099511628211ULL;
    }
    return @{
        @"xml" : xml,
        @"pageKey" : [NSString stringWithFormat:@"ios-source-%016llx", (unsigned long long)hash],
        @"candidates" : candidates,
        @"escapeGesture" : candidates.count == 0 && containsCounter(snapshot) ? @"preview_tap" : @"edge_back",
        @"nodeCount" : @(count)
    };
}
+ (NSDictionary *)targetForAction:(NSDictionary *)action candidates:(NSArray<NSDictionary *> *)candidates {
    if (![action isKindOfClass:NSDictionary.class] || !numbers(action[@"pos"]) ||
        ![candidates isKindOfClass:NSArray.class])
        return nil;
    NSString *act = str(action[@"act"]);
    BOOL click = [act isEqual:@"CLICK"];
    BOOL scroll = [@[
        @"SCROLL_BOTTOM_UP", @"SCROLL_TOP_DOWN", @"SCROLL_LEFT_RIGHT", @"SCROLL_RIGHT_LEFT",
        @"SCROLL_BOTTOM_UP_N"
    ] containsObject:act];
    if (!click && !scroll)
        return nil;
    NSArray *p = action[@"pos"];
    if ([p[0] doubleValue] < 0 || [p[1] doubleValue] < 0 || [p[2] doubleValue] <= [p[0] doubleValue] ||
        [p[3] doubleValue] <= [p[1] doubleValue])
        return nil;
    NSDictionary *found = nil;
    NSMutableArray *alternatives=[NSMutableArray array];
    for (id c in candidates) {
        if (![c isKindOfClass:NSDictionary.class] || ![c[click ? @"clickable" : @"scrollable"] boolValue] ||
            !numbers(c[@"bounds"]))
            continue;
        NSString *direction = [act isEqual:@"SCROLL_BOTTOM_UP_N"] ? @"SCROLL_BOTTOM_UP" : act;
        if (scroll && [c[@"scrollDirections"] isKindOfClass:NSArray.class] &&
            ![c[@"scrollDirections"] containsObject:direction]) continue;
        BOOL match = YES;
        for (NSUInteger i = 0; i < 4; i++)
            // XML and guard operation keys use the same integer event region.
            // A distance tolerance can steal a neighboring region or reject it
            // as ambiguous even though the core selected an exact region.
            if (![[NSString stringWithFormat:@"%.0f",[p[i] doubleValue]]
                  isEqual:[NSString stringWithFormat:@"%.0f",[c[@"bounds"][i] doubleValue]]])
                match = NO;
        if (match) {
            if (found) {
                if (!click || [found isEqual:c]) return nil;
                // Only truly equivalent rounded event regions may share a live lookup.
                // Nearby but distinct targets remain ambiguous, never silently merged.
                for (NSUInteger i=0;i<4;i++)
                    if (![[NSString stringWithFormat:@"%.0f",[found[@"bounds"][i] doubleValue]]
                          isEqual:[NSString stringWithFormat:@"%.0f",[c[@"bounds"][i] doubleValue]]]) return nil;
            } else found = c;
            [alternatives addObject:c];
        }
    }
    if (alternatives.count>1) {
        NSMutableDictionary *group=[found mutableCopy];group[@"alternatives"]=alternatives;return group;
    }
    return found;
}
+ (NSDictionary *)uniqueLiveTargetForCandidates:(NSArray<NSDictionary *> *)candidates lookup:(NSDictionary * (^)(NSDictionary *candidate))lookup {
    return [self uniqueLiveTargetForCandidates:candidates lookup:lookup diagnostics:[NSMutableDictionary dictionary]];
}
+ (NSDictionary *)uniqueLiveTargetForCandidates:(NSArray<NSDictionary *> *)candidates lookup:(NSDictionary * (^)(NSDictionary *candidate))lookup diagnostics:(NSMutableDictionary *)diagnostics {
    [diagnostics removeAllObjects];
    NSMutableArray *lookups=[NSMutableArray array];
    diagnostics[@"lookups"]=lookups;
    NSDictionary *resolved=nil;
    for (NSDictionary *candidate in candidates) {
        NSDictionary *status=lookup(candidate);
        NSMutableDictionary *entry=[status mutableCopy] ?: [NSMutableDictionary dictionary];
        [entry removeObjectForKey:@"element"]; // XCUIElement is not JSON data.
        entry[@"candidatePath"]=candidate[@"path"] ?: @"";
        [lookups addObject:entry];
        if (![status[@"complete"] boolValue]) {
            diagnostics[@"reason"]=status[@"reason"] ?: @"lookup_incomplete";
            return nil;
        }
        id element=status[@"element"];
        if (element && element!=NSNull.null) {
            if (resolved) {
                diagnostics[@"reason"]=@"ambiguous_hittable_targets";
                return nil;
            }
            resolved=@{@"element":element,@"candidate":candidate};
        }
    }
    diagnostics[@"reason"]=resolved ? @"matched" : @"no_hittable_target";
    return resolved;
}
+ (NSPredicate *)livePredicateForTarget:(NSDictionary *)target {
    NSPredicate *identifier=[NSPredicate predicateWithFormat:@"identifier == %@",str(target[@"identifier"])];
    // liveKey includes both identity fields. Secure labels are redacted in both
    // snapshots and candidates, so never compare them with unredacted live text.
    if ([target[@"secure"] boolValue]) return identifier;
    return [NSCompoundPredicate andPredicateWithSubpredicates:@[identifier,
        [NSPredicate predicateWithFormat:@"label == %@",str(target[@"label"])]]];
}
+ (BOOL)target:(NSDictionary *)target matchesLiveBounds:(NSArray<NSNumber *> *)bounds {
    NSArray *expected = target[@"originalBounds"] ?: target[@"bounds"];
    if (!numbers(expected) || !numbers(bounds))
        return NO;
    double w = [bounds[2] doubleValue] - [bounds[0] doubleValue],
           h = [bounds[3] doubleValue] - [bounds[1] doubleValue];
    double ew = [expected[2] doubleValue] - [expected[0] doubleValue],
           eh = [expected[3] doubleValue] - [expected[1] doubleValue];
    if (w <= 0 || h <= 0 || ew <= 0 || eh <= 0)
        return NO;
    double iw = fmax(0, fmin([bounds[2] doubleValue], [expected[2] doubleValue]) -
                            fmax([bounds[0] doubleValue], [expected[0] doubleValue]));
    double ih = fmax(0, fmin([bounds[3] doubleValue], [expected[3] doubleValue]) -
                            fmax([bounds[1] doubleValue], [expected[1] doubleValue]));
    double intersection = iw * ih, unionArea = w * h + ew * eh - intersection;
    return unionArea > 0 && intersection / unionArea >= 0.85;
}
@end
