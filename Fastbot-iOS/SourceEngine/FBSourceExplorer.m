#import "FBSourceExplorer.h"
#import "FBExplorationGuard.h"
#import "FBSourceEngine.h"
#import "FBTreeAdapter.h"
#import <QuartzCore/QuartzCore.h>

static NSError *FBError(NSString *message) {
    return [NSError errorWithDomain:@"FastbotSourceExplorer"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}
static NSString *FBKind(XCUIElementType type) {
    switch (type) {
    case XCUIElementTypeKeyboard:
        return @"keyboard";
    case XCUIElementTypeKey:
        return @"key";
    case XCUIElementTypeStatusBar:
        return @"statusBar";
    case XCUIElementTypeButton:
        return @"button";
    case XCUIElementTypeLink:
        return @"link";
    case XCUIElementTypeCell:
        return @"cell";
    case XCUIElementTypeSwitch:
        return @"switch";
    case XCUIElementTypeTextField:
        return @"textField";
    case XCUIElementTypeSecureTextField:
        return @"secureTextField";
    case XCUIElementTypeTextView:
        return @"textView";
    case XCUIElementTypeScrollView:
        return @"scrollView";
    case XCUIElementTypeTable:
        return @"table";
    case XCUIElementTypeCollectionView:
        return @"collectionView";
    case XCUIElementTypeWebView:
        return @"webView";
    case XCUIElementTypeStaticText:
        return @"staticText";
    default:
        return @"other";
    }
}
// One remote snapshot, then local traversal. Do not query every live node separately.
static NSDictionary *FBNormalize(id<XCUIElementSnapshot> node, NSUInteger depth, NSUInteger *remaining, NSArray *nativePath, BOOL *inputVisible, NSArray *viewport) {
    if (!node || ![FBTreeAdapter consumeSnapshotNodeAtDepth:depth remaining:remaining])
        return nil;
    NSArray *rawChildren = node.children;
    NSMutableArray *childHints = [NSMutableArray array];
    for (id<XCUIElementSnapshot> child in rawChildren) {
        CGRect childFrame=child.frame;
        [childHints addObject:@{@"identifier": child.identifier ?: @"",
            @"frame":@[@(childFrame.origin.x),@(childFrame.origin.y),@(childFrame.size.width),@(childFrame.size.height)]}];
    }
    CGRect f = node.frame;
    NSDictionary *hint=@{@"kind":FBKind(node.elementType), @"identifier":node.identifier ?: @"",
        @"children":childHints, @"frame":@[@(f.origin.x),@(f.origin.y),@(f.size.width),@(f.size.height)]};
    if ([FBTreeAdapter isSystemInputContainer:hint]) {
        // Preserve only context, never keyboard labels, suggestions or input values.
        if ([FBTreeAdapter inputVisibleForPrunedNode:hint viewport:viewport]) *inputVisible = YES;
        return nil;
    }
    BOOL secure = node.elementType == XCUIElementTypeSecureTextField;
    NSMutableArray *children = [NSMutableArray array];
    NSUInteger childIndex = 0;
    for (id<XCUIElementSnapshot> child in rawChildren) {
        NSDictionary *desc = FBNormalize(child, depth + 1, remaining, [nativePath arrayByAddingObject:@(childIndex++)], inputVisible, viewport);
        if (desc)
            [children addObject:desc];
    }
    // Input values never enter XML or persisted snapshots.
    return @{
        @"type" : @(node.elementType),
        @"nativePath" : nativePath,
        @"kind" : FBKind(node.elementType),
        @"identifier" : node.identifier ?: @"",
        @"label" : secure ? @"" : (node.label ?: @""),
        @"value" : @"",
        @"enabled" : @(node.enabled),
        @"selected" : @(node.selected),
        @"frame" : @[ @(f.origin.x), @(f.origin.y), @(f.size.width), @(f.size.height) ],
        @"children" : children
    };
}
static BOOL FBAllowAlert(XCUIElement *alert) {
    for (NSString *label in @[
             @"使用App时允许", @"使用 App 时允许", @"使用应用时允许", @"允许一次", @"允许",
             @"Allow While Using App", @"Allow Once", @"Allow", @"好", @"OK"
         ]) {
        XCUIElement *button = alert.buttons[label];
        if (button.exists && button.hittable) {
            [button tap];
            NSLog(@"SOURCE_PERMISSION handled=%@", label);
            return YES;
        }
    }
    return NO;
}
static XCUIElement *FBFreshSingleTarget(XCUIApplication *app, NSDictionary *target, NSTimeInterval groupDeadline, NSMutableDictionary *diagnostic) {
    diagnostic[@"complete"]=@NO;
    diagnostic[@"expectedMatches"]=target[@"liveMatchCount"] ?: @0;
    diagnostic[@"matches"]=@0;
    diagnostic[@"inspected"]=@0;
    if (CACurrentMediaTime() >= groupDeadline) { diagnostic[@"reason"]=@"group_timeout"; return nil; }
    XCUIElementQuery *query = [app descendantsMatchingType:[target[@"type"] unsignedIntegerValue]];
    NSString *identifier = target[@"identifier"], *label = target[@"label"];
    query = [query matchingPredicate:[FBTreeAdapter livePredicateForTarget:target]];
    XCUIElement *match = nil;
    NSUInteger matches = 0, inspected = 0;
    NSTimeInterval lookupDeadline = MIN(groupDeadline, CACurrentMediaTime() + (label.length || identifier.length ? 4 : 12));
    for (XCUIElement *element in query.allElementsBoundByIndex) {
        diagnostic[@"inspected"]=@(++inspected);
        if (CACurrentMediaTime() > lookupDeadline) { diagnostic[@"reason"]=@"query_timeout"; return nil; }
        if (inspected > (label.length || identifier.length ? 32 : 256)) { diagnostic[@"reason"]=@"query_limit"; return nil; }
        id<XCUIElementSnapshot> live = [element snapshotWithError:nil];
        if (!live) { diagnostic[@"reason"]=@"snapshot_failed"; return nil; }
        if (!live.enabled) continue;
        CGRect f = live.frame;
        if (![FBTreeAdapter target:target matchesLiveBounds:@[
                @(f.origin.x), @(f.origin.y), @(CGRectGetMaxX(f)), @(CGRectGetMaxY(f))]]) continue;
        diagnostic[@"matches"]=@(++matches);
        // Same-identity RN ancestor/leaf pairs must agree with the snapshot count.
        if (element.hittable) match = element;
    }
    // Native calls cannot be preempted; never treat an over-budget scan as complete.
    if (CACurrentMediaTime() > lookupDeadline) { diagnostic[@"reason"]=@"query_timeout"; return nil; }
    if (matches>0 && matches != [target[@"liveMatchCount"] unsignedIntegerValue]) {
        diagnostic[@"reason"]=@"live_match_count_mismatch"; return nil;
    }
    diagnostic[@"complete"]=@YES;
    diagnostic[@"reason"]=matches==0 ? @"no_live_match" : match ? @"matched" : @"not_hittable";
    return matches == [target[@"liveMatchCount"] unsignedIntegerValue] ? match : nil;
}
static XCUIElement *FBFreshTarget(XCUIApplication *app, NSDictionary *target, NSDictionary **resolved, NSMutableDictionary *diagnostic) {
    NSArray *alternatives=target[@"alternatives"] ?: @[target];
    NSTimeInterval deadline=CACurrentMediaTime()+12;
    NSDictionary *result=[FBTreeAdapter uniqueLiveTargetForCandidates:alternatives lookup:^NSDictionary *(NSDictionary *candidate) {
        NSMutableDictionary *status=[NSMutableDictionary dictionary];
        XCUIElement *element=FBFreshSingleTarget(app,candidate,deadline,status);
        if (element) status[@"element"]=element;
        return status;
    } diagnostics:diagnostic];
    if (CACurrentMediaTime() >= deadline) { diagnostic[@"reason"]=@"group_timeout"; return nil; }
    if (resolved) *resolved=result[@"candidate"];
    return result[@"element"];
}
static XCUIElement *FBBackButton(XCUIApplication *app) {
    for (NSString *label in @[ @"返回", @"Back", @"后退", @"关闭", @"Close", @"取消", @"Cancel", @"完成", @"Done" ]) {
        XCUIElementQuery *q =
            [app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label == %@", label]];
        if (q.count == 1 && q.firstMatch.enabled && q.firstMatch.hittable)
            return q.firstMatch;
    }
    return nil;
}
static BOOL FBBack(XCUIApplication *app, NSString *gesture) {
    XCUIElement *button = FBBackButton(app);
    if (button) {
        [button tap];
        return YES;
    }
    if (!app.exists || app.state != XCUIApplicationStateRunningForeground || CGRectIsEmpty(app.frame)) return NO;
    if ([gesture isEqualToString:@"preview_tap"]) {
        [app tap];
    } else {
        XCUICoordinate *edge = [app coordinateWithNormalizedOffset:CGVectorMake(0.01, 0.5)];
        [edge pressForDuration:0.1 thenDragToCoordinate:
            [app coordinateWithNormalizedOffset:CGVectorMake(0.8, 0.5)]];
    }
    return YES;
}
static void FBAudit(NSFileHandle *file, NSDictionary *event) {
    NSMutableDictionary *entry = [event mutableCopy];
    entry[@"timestamp"] = [[NSISO8601DateFormatter new] stringFromDate:[NSDate date]];
    NSData *data = [NSJSONSerialization dataWithJSONObject:entry options:0 error:nil];
    if (data) {
        [file writeData:data];
        [file writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [file synchronizeFile];
    }
}
@implementation FBSourceExplorer
- (BOOL)runWithTestCase:(XCTestCase *)testCase
            environment:(NSDictionary<NSString *, NSString *> *)env
                  error:(NSError **)error {
    NSString *bundle = env[@"BUNDLEID"];
    NSInteger minutes = [env[@"duration"] integerValue];
    if (!bundle.length || minutes < 1) {
        if (error)
            *error = FBError(@"BUNDLEID and positive duration are required");
        return NO;
    }
    NSTimeInterval throttle = MAX(0, [env[@"throttle"] doubleValue] / 1000.0);
    NSString *runID = env[@"FASTBOT_RUN_ID"];
    if (!runID.length) runID = NSUUID.UUID.UUIDString;
    if ([runID rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"] invertedSet]].location != NSNotFound ||
        !runID.length || runID.length > 100) {
        if (error) *error = FBError(@"Invalid evidence run identifier");
        return NO;
    }
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *directory = [[documents stringByAppendingPathComponent:@"fastbot-evidence"]
        stringByAppendingPathComponent:runID];
    NSString *stopPath = [directory stringByAppendingPathComponent:@"stop.json"];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:error])
        return NO;
    NSString *auditPath = [directory stringByAppendingPathComponent:@"exploration.jsonl"];
    [[NSFileManager defaultManager] createFileAtPath:auditPath contents:nil attributes:nil];
    NSFileHandle *audit = [NSFileHandle fileHandleForWritingAtPath:auditPath];
    FBSourceEngine *engine = [[FBSourceEngine alloc] initWithStorageDirectory:directory
                                                                     bundleID:bundle
                                                                         seed:42];
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:bundle];
    XCUIApplication *springboard =
        [[XCUIApplication alloc] initWithBundleIdentifier:@"com.apple.springboard"];
    id monitor = [testCase addUIInterruptionMonitorWithDescription:@"Fastbot permissions"
                                                           handler:^BOOL(XCUIElement *alert) {
                                                               return FBAllowAlert(alert);
                                                           }];
    if (!engine || !audit) {
        if (error)
            *error = FBError(@"Cannot initialize source engine or audit file");
        [audit closeFile];
        [testCase removeUIInterruptionMonitor:monitor];
        return NO;
    }
    // Keep failures alive across the per-action autorelease pools. Publish only on return.
    NSError *runError = nil;
    FBExplorationGuard *guard = [FBExplorationGuard new];
    NSUInteger steps = 0, rejected = 0, failures = 0, recoveries = 0;
    BOOL success = NO, selectionExhausted = NO;
    NSString *stopReason = @"time_budget";
    NSString *selectionExhaustedContext = nil;
    NSString *lastXML = nil;
    NSMutableSet *diagnosticPages = [NSMutableSet set];
    NSTimeInterval deadline = CACurrentMediaTime() + minutes * 60;
    @try {
        NSMutableDictionary *launch = [NSMutableDictionary dictionary];
        for (NSString *pair in [env[@"launchenv"] componentsSeparatedByString:@":"]) {
            NSRange separator = [pair rangeOfString:@"="];
            if (separator.location != NSNotFound)
                launch[[pair substringToIndex:separator.location]] =
                    [pair substringFromIndex:separator.location + 1];
        }
        app.launchEnvironment = launch;
        [app launch];
        NSLog(@"SOURCE_ENGINE engine=android-reuseq-source tree=xctest-accessibility seed=42 artifact=%@",
              directory);
        while (CACurrentMediaTime() < deadline) {
            @autoreleasepool {
                NSDictionary *stop = [NSJSONSerialization JSONObjectWithData:
                    [NSData dataWithContentsOfFile:stopPath] ?: [NSData data] options:0 error:nil];
                if ([stop[@"runID"] isEqualToString:runID] &&
                    [@[@"js_error", @"validation_stop"] containsObject:stop[@"reason"]]) {
                    stopReason = [stop[@"reason"] isEqual:@"js_error"] ? @"external_js_error" : @"validation_stop";
                    runError = FBError(@"Host requested exploration stop; preserving failure evidence");
                    FBAudit(audit, @{@"kind":@"stop_requested", @"reason":stopReason});
                    break;
                }
                if (springboard.alerts.firstMatch.exists && FBAllowAlert(springboard.alerts.firstMatch))
                    continue;
                if (app.alerts.firstMatch.exists && FBAllowAlert(app.alerts.firstMatch))
                    continue;
                if (app.state != XCUIApplicationStateRunningForeground)
                    [app activate];
                NSError *snapshotError = nil;
                NSTimeInterval started = CACurrentMediaTime();
                id<XCUIElementSnapshot> snapshot = [app snapshotWithError:&snapshotError];
                NSUInteger remaining = 5000;
                BOOL inputVisible = NO;
                CGRect viewportFrame=snapshot.frame;
                NSArray *viewport=@[@(viewportFrame.origin.x),@(viewportFrame.origin.y),@(viewportFrame.size.width),@(viewportFrame.size.height)];
                NSMutableDictionary *normalized = [FBNormalize(snapshot, 0, &remaining, @[], &inputVisible, viewport) mutableCopy];
                if (normalized) normalized[@"inputVisible"] = @(inputVisible);
                NSDictionary *page =
                    normalized ? [FBTreeAdapter pageFromSnapshot:normalized bundleID:bundle] : nil;
                if (normalized && remaining > 0) {
                    failures = 0;
                    NSDictionary *effect = [guard observeSnapshot:normalized];
                    if (effect)
                        FBAudit(audit, effect);
                }
                NSArray *candidates = page[@"candidates"];
                if (page && remaining > 0) {
                    lastXML = page[@"xml"];
                    NSDictionary *checkpoint = @{@"xml":lastXML, @"pageKey":page[@"pageKey"],
                        @"fingerprint":guard.fingerprint, @"nodeCount":page[@"nodeCount"] ?: @0,
                        @"timestamp":[[NSISO8601DateFormatter new] stringFromDate:NSDate.date],
                        @"snapshot":normalized};
                    NSError *checkpointError = nil;
                    NSData *checkpointData = [NSJSONSerialization dataWithJSONObject:checkpoint options:0 error:&checkpointError];
                    if (!checkpointData || ![checkpointData writeToFile:
                            [directory stringByAppendingPathComponent:@"checkpoint.json"]
                            options:NSDataWritingAtomic error:&checkpointError]) {
                        stopReason = @"evidence_write_failed";
                        runError = checkpointError ?: FBError(@"Cannot persist exploration checkpoint");
                        break;
                    }
                }
                BOOL canGoBack=app.state == XCUIApplicationStateRunningForeground;
                NSString *actionContext=[guard exhaustionContextForCandidates:candidates canGoBack:canGoBack];
                if (selectionExhausted && ![selectionExhaustedContext isEqual:actionContext])
                    selectionExhausted = NO;
                BOOL exhaustionCandidate = page && remaining > 0 &&
                    (selectionExhausted || ![guard hasAvailableActionForCandidates:candidates
                        canGoBack:canGoBack]);
                BOOL confirmedExhaustion = [guard confirmExhaustion:exhaustionCandidate
                                                               atTime:CACurrentMediaTime() context:actionContext];
                if (exhaustionCandidate && !confirmedExhaustion) {
                    FBAudit(audit, @{@"kind":@"settling", @"reason":@"confirm_exhaustion",
                        @"fingerprint":guard.fingerprint, @"candidateCount":@(candidates.count)});
                    [NSThread sleepForTimeInterval:0.5];
                    continue;
                }
                if (confirmedExhaustion) {
                    NSUInteger reopened = [guard beginNextPassForCandidates:candidates canGoBack:canGoBack];
                    if (reopened) {
                        selectionExhausted = NO;
                        FBAudit(audit, @{@"kind":@"exploration_pass", @"reason":@"revisit_effective_transitions",
                            @"reopenedActions":@(reopened), @"fingerprint":guard.fingerprint});
                        continue;
                    }
                    if (recoveries >= 2) {
                        stopReason = @"no_progress_exhausted";
                        FBAudit(audit, @{
                            @"kind" : @"exploration_exhausted",
                            @"reason" : stopReason,
                            @"fingerprint" : guard.fingerprint,
                            @"candidateCount" : @(candidates.count)
                        });
                        runError =
                            FBError(@"No unblocked accessibility actions after two bounded recoveries");
                        break;
                    }
                    ++recoveries;
                    selectionExhausted = NO;
                    FBAudit(audit, @{
                        @"kind" : @"recovery",
                        @"reason" : @"no_available_action",
                        @"method" : @"relaunch_without_data_clear",
                        @"attempt" : @(recoveries),
                        @"fingerprint" : guard.fingerprint
                    });
                    NSLog(@"SOURCE_RECOVERY attempt=%lu reason=no_available_action",
                          (unsigned long)recoveries);
                    [guard clearPending];
                    [app terminate];
                    [app launch];
                    failures = 0;
                    [NSThread sleepForTimeInterval:MAX(throttle, 0.5)];
                    continue;
                }
                if (!page || remaining == 0) {
                    FBAudit(audit, @{
                        @"kind" : @"snapshot_rejected",
                        @"reason" : remaining == 0 ? @"node_limit" : @"no_actionable_elements",
                        @"nodeCount" : page[@"nodeCount"] ?: @0
                    });
                    if (++failures >= 10) {
                        stopReason = @"snapshot_unavailable";
                        runError = FBError(@"No usable accessibility tree after 10 attempts");
                        break;
                    }
                    [NSThread sleepForTimeInterval:MAX(throttle, 0.5)];
                    continue;
                }
                lastXML = page[@"xml"];
                if (diagnosticPages.count < 12 && ![diagnosticPages containsObject:page[@"pageKey"]]) {
                    [diagnosticPages addObject:page[@"pageKey"]];
                    NSData *nativeData = [NSJSONSerialization dataWithJSONObject:normalized options:0 error:nil];
                    if (![nativeData writeToFile:[directory stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"native-tree-%@.json", page[@"pageKey"]]]
                            options:NSDataWritingAtomic error:nil]) {
                        stopReason = @"evidence_write_failed";
                        runError = FBError(@"Cannot persist native snapshot");
                        break;
                    }
                    XCTAttachment *tree = [XCTAttachment attachmentWithData:nativeData
                        uniformTypeIdentifier:@"public.json"];
                    tree.name = [@"source-native-tree-" stringByAppendingString:page[@"pageKey"]];
                    tree.lifetime = XCTAttachmentLifetimeKeepAlways;
                    [testCase addAttachment:tree];
                }
                NSError *decisionError = nil;
                NSDictionary *action = [engine nextActionForXML:lastXML
                                                        pageKey:page[@"pageKey"]
                                               excludingActions:[guard exclusionsForCandidates:candidates]
                                                          error:&decisionError];
                if (!action) {
                    stopReason = @"engine_error";
                    FBAudit(audit, @{
                        @"kind" : @"engine_error",
                        @"reason" : decisionError.localizedDescription ?: @"no action"
                    });
                    runError = decisionError ?: FBError(@"Engine returned no action");
                    break;
                }
                NSDictionary *selectedTarget = nil;
                NSMutableDictionary *targetDiagnostic=[NSMutableDictionary dictionary];
                NSString *act = action[@"act"];
                NSString *state = [action[@"sid"] length] ? action[@"sid"] : page[@"pageKey"];
                BOOL executed = NO;
                NSString *navigationMethod = nil;
                NSString *reason = @"unsupported_action";
                if ([act isEqualToString:@"NOP"] &&
                    [action[@"reason"] isEqualToString:@"no_available_action"]) {
                    selectionExhausted = YES;
                    selectionExhaustedContext = actionContext;
                    reason = @"no_available_action";
                }
                if ([act isEqualToString:@"BACK"]) {
                    navigationMethod = FBBackButton(app) ? @"native_button" : page[@"escapeGesture"];
                    executed = FBBack(app, page[@"escapeGesture"]);
                    reason = @"no_native_back_target";
                } else if ([act isEqualToString:@"ACTIVATE"] || [act isEqualToString:@"START"]) {
                    [app activate];
                    executed = YES;
                } else if ([act isEqualToString:@"RESTART"]) {
                    [app terminate];
                    [app launch];
                    executed = YES;
                } else {
                    NSDictionary *target = [FBTreeAdapter targetForAction:action candidates:candidates];
                    NSDictionary *resolvedTarget=nil;
                    XCUIElement *element = target ? FBFreshTarget(app, target, &resolvedTarget, targetDiagnostic) : nil;
                    target = resolvedTarget ?: target;
                    selectedTarget = target;
                    if (!selectionExhausted)
                        reason = target ? @"target_stale_or_not_hittable" : @"no_unique_action_target";
                    if (element) {
                        if ([act isEqualToString:@"CLICK"]) {
                            [element tap];
                            NSString *text = action[@"text"];
                            if ([target[@"editable"] boolValue] && [text isKindOfClass:NSString.class] &&
                                text.length && text.length <= 128)
                                [element typeText:text];
                            executed = YES;
                        } else if ([act isEqualToString:@"LONG_CLICK"]) {
                            [element pressForDuration:1];
                            executed = YES;
                        } else if ([target[@"scrollable"] boolValue]) {
                            if ([act isEqualToString:@"SCROLL_BOTTOM_UP"] ||
                                [act isEqualToString:@"SCROLL_BOTTOM_UP_N"]) {
                                [element swipeUp];
                                executed = YES;
                            } else if ([act isEqualToString:@"SCROLL_TOP_DOWN"]) {
                                [element swipeDown];
                                executed = YES;
                            } else if ([act isEqualToString:@"SCROLL_RIGHT_LEFT"]) {
                                [element swipeLeft];
                                executed = YES;
                            } else if ([act isEqualToString:@"SCROLL_LEFT_RIGHT"]) {
                                [element swipeRight];
                                executed = YES;
                            }
                        }
                    }
                }
                NSMutableDictionary *record = [@{
                    @"kind" : @"action",
                    @"state" : state,
                    @"pageKey" : page[@"pageKey"],
                    @"act" : act ?: @"",
                    @"executed" : @(executed),
                    @"reason" : executed ? @"executed" : reason,
                    @"candidateCount" : @(candidates.count),
                    @"nodeCount" : page[@"nodeCount"] ?: @0,
                    @"elapsedMs" : @((CACurrentMediaTime() - started) * 1000)
                } mutableCopy];
                if (targetDiagnostic.count) record[@"targetResolution"]=targetDiagnostic;
                if (selectedTarget) {
                    record[@"targetLabel"] = selectedTarget[@"label"] ?: @"";
                    record[@"recognition"] = selectedTarget[@"recognition"] ?: @"native_role";
                    record[@"liveMatchCount"] = selectedTarget[@"liveMatchCount"] ?: @1;
                }
                record[@"inferredCandidateCount"] = @([[candidates filteredArrayUsingPredicate:
                    [NSPredicate predicateWithFormat:@"recognition == %@", @"inferred_label"]] count]);
                if (action[@"pos"])
                    record[@"bounds"] = action[@"pos"];
                if ([act isEqualToString:@"BACK"])
                    record[@"navigationMethod"] = navigationMethod ?: @"unavailable";
                record[@"beforeFingerprint"] = guard.fingerprint;
                [guard recordAction:action executed:executed reason:reason];
                record[@"stalledRejectionCount"] = @(guard.stalledRejectionCount);
                record[@"blockedActionCount"] = @(guard.blockedCount);
                FBAudit(audit, record);
                if (executed) {
                    ++steps;
                    failures = 0;
                    NSLog(@"state %@ action %@ throttle %.2f source=xctest", state, act, throttle);
                } else {
                    ++rejected;
                    if (guard.stalledRejectionCount >= 15) {
                        stopReason = @"consecutive_rejections";
                        runError = FBError(
                            @"15 rejected selections without eliminating or retrying a fresh candidate");
                        break;
                    }
                }
                [NSThread sleepForTimeInterval:MAX(throttle, 0.1)];
            }
        }
        success =
            [stopReason isEqualToString:@"time_budget"] && CACurrentMediaTime() >= deadline && steps > 0;
        if (!success && !runError)
            runError = FBError(@"Source exploration ended without completing its budget");
    } @catch (NSException *exception) {
        stopReason = @"exception";
        runError = FBError([NSString stringWithFormat:@"Source explorer stopped: %@", exception.name]);
    } @finally {
        [testCase removeUIInterruptionMonitor:monitor];
        NSUInteger states = engine.stateCount;
        [engine close];
        FBAudit(audit, @{
            @"kind" : @"summary",
            @"executed" : @(steps),
            @"rejected" : @(rejected),
            @"states" : @(states),
            @"completed" : @(success),
            @"stopReason" : stopReason,
            @"noEffectCount" : @(guard.noEffectCount),
            @"progressCount" : @(guard.progressCount),
            @"blockedActionCount" : @(guard.blockedCount),
            @"recoveries" : @(recoveries),
            @"finalOutcomePending" : @(steps > guard.noEffectCount + guard.progressCount)
        });
        [audit closeFile];
        NSData *data = [NSData dataWithContentsOfFile:auditPath];
        if (data) {
            XCTAttachment *a = [XCTAttachment attachmentWithData:data uniformTypeIdentifier:@"public.json"];
            a.name = @"source-exploration.jsonl";
            a.lifetime = XCTAttachmentLifetimeKeepAlways;
            [testCase addAttachment:a];
        }
        if (lastXML) {
            XCTAttachment *a = [XCTAttachment attachmentWithString:lastXML];
            a.name = @"source-last-tree.xml";
            a.lifetime = XCTAttachmentLifetimeKeepAlways;
            [testCase addAttachment:a];
        }
        NSLog(@"SOURCE_SUMMARY completed=%d executed=%lu rejected=%lu", success, (unsigned long)steps,
              (unsigned long)rejected);
    }
    if (error)
        *error = runError;
    return success;
}
@end
