#import <Foundation/Foundation.h>
#import "FBExplorationGuard.h"
#define CHECK(...) do { if(!(__VA_ARGS__)){NSLog(@"FAIL line %d",__LINE__);exit(1);} }while(0)
static NSDictionary *snapshot(NSString *label, NSNumber *y){return @{@"kind":@"other",@"frame":@[@0,@0,@320,@640],@"children":@[@{@"kind":@"button",@"identifier":@"item",@"label":label,@"frame":@[@0,y,@100,@40]}]};}
int main(){@autoreleasepool{
 FBExplorationGuard *g=[FBExplorationGuard new]; NSDictionary *a=@{@"act":@"SCROLL_TOP_DOWN",@"pos":@[@0,@0,@320,@640]}; NSArray *c=@[@{@"bounds":a[@"pos"],@"scrollable":@YES}];
 [g observeSnapshot:snapshot(@"Item",@0)]; NSString *first=g.fingerprint;
 for(int i=0;i<2;i++){[g recordAction:a executed:YES reason:@""];NSDictionary *e=[g observeSnapshot:snapshot(@"Item",@0)];CHECK([e[@"effect"] isEqual:@"no_observable_change"]);}
 CHECK(g.noEffectCount==2);CHECK([g exclusionsForCandidates:c].count==1);CHECK([g hasAvailableActionForCandidates:c canGoBack:NO]);
 [g observeSnapshot:snapshot(@"Next",@0)];CHECK([g exclusionsForCandidates:c].count==0);
 [g observeSnapshot:snapshot(@"00:01",@0)];NSString *timer=g.fingerprint;[g observeSnapshot:snapshot(@"00:02",@0)];CHECK([timer isEqual:g.fingerprint]);
 [g observeSnapshot:snapshot(@"Item",@0)];CHECK([first isEqual:g.fingerprint]);
 for(int i=0;i<2;i++){[g recordAction:a executed:YES reason:@""];[g observeSnapshot:snapshot(@"Item",@100)];[g observeSnapshot:snapshot(@"Item",@0)];}
 CHECK(g.progressCount==2);CHECK([g exclusionsForCandidates:c].count==1);
 [g recordAction:@{@"act":@"BACK"} executed:NO reason:@"no navigation"];CHECK(![g hasAvailableActionForCandidates:@[] canGoBack:YES]);
 [g clearPending];CHECK(![g hasAvailableActionForCandidates:@[] canGoBack:YES]);
 FBExplorationGuard *fresh=[FBExplorationGuard new];[fresh observeSnapshot:snapshot(@"A",@0)];
 NSDictionary *clipped=@{@"act":@"CLICK",@"pos":@[@0,@1,@100,@40]};[fresh recordAction:clipped executed:NO reason:@"rejected"];
 CHECK([fresh exclusionsForCandidates:@[@{@"bounds":@[@0,@1,@100,@40],@"clickable":@YES}]].count==1);
 NSArray *different=@[@{@"bounds":@[@0,@0,@100,@40],@"clickable":@YES}];
 CHECK([fresh exclusionsForCandidates:different].count==1);CHECK([fresh hasAvailableActionForCandidates:different canGoBack:NO]);
 CHECK([fresh exclusionsForCandidates:@[]].count==1);CHECK([[fresh exclusionsForCandidates:@[]][0][@"pos"] isEqual:clipped[@"pos"]]);
 [fresh recordAction:clipped executed:YES reason:@""];[fresh recordAction:@{@"act":@"NOP"} executed:NO reason:@""];CHECK([fresh observeSnapshot:snapshot(@"A",@0)]==nil);
 [fresh recordAction:clipped executed:YES reason:@""];[fresh clearPending];CHECK([fresh observeSnapshot:snapshot(@"B",@20)]==nil);CHECK(fresh.progressCount==0);
 FBExplorationGuard *retained=[FBExplorationGuard new];
 @autoreleasepool { [retained observeSnapshot:snapshot(@"Retained",@0)]; [retained recordAction:@{@"act":@"CLICK",@"pos":@[@0,@0,@100,@40]} executed:YES reason:@""]; }
 @autoreleasepool { CHECK([[retained observeSnapshot:snapshot(@"Retained",@0)][@"effect"] isEqual:@"no_observable_change"]); [retained recordAction:@{@"act":@"CLICK",@"pos":@[@0,@0,@100,@40]} executed:NO reason:@"rejected"]; }
 @autoreleasepool { NSArray *fractional=@[@{@"bounds":@[@0.4,@0.4,@100.4,@40.4],@"clickable":@YES}]; NSArray *ex=[retained exclusionsForCandidates:fractional]; CHECK(ex.count==1); CHECK([NSJSONSerialization isValidJSONObject:ex]); CHECK([ex[0][@"pos"][0] isEqual:@0]); CHECK([ex[0][@"pos"][2] isEqual:@100]); }
 FBExplorationGuard *ties=[FBExplorationGuard new]; [ties observeSnapshot:snapshot(@"Ties",@0)];
 [ties recordAction:@{@"act":@"CLICK",@"pos":@[@0.5,@2.5,@100.5,@40.5]} executed:NO reason:@"rejected"];
 NSArray *tiesEx=[ties exclusionsForCandidates:@[@{@"bounds":@[@0,@2,@100,@40],@"clickable":@YES}]]; CHECK(tiesEx.count==1);
 FBExplorationGuard *web=[FBExplorationGuard new]; [web observeSnapshot:snapshot(@"Web",@0)];
 NSArray *webCandidates=@[@{@"bounds":@[@0,@0,@320,@640],@"scrollable":@YES,@"scrollDirections":@[@"SCROLL_TOP_DOWN",@"SCROLL_BOTTOM_UP",@"SCROLL_LEFT_RIGHT",@"SCROLL_RIGHT_LEFT"]}];
 for(NSString *act in @[@"SCROLL_TOP_DOWN",@"SCROLL_BOTTOM_UP",@"SCROLL_LEFT_RIGHT",@"SCROLL_RIGHT_LEFT"]){[web recordAction:@{@"act":act,@"pos":@[@0,@0,@320,@640]} executed:NO reason:@"rejected"];}
 CHECK([web exclusionsForCandidates:webCandidates].count==4); CHECK(![web hasAvailableActionForCandidates:webCandidates canGoBack:NO]);
 FBExplorationGuard *settling=[FBExplorationGuard new]; [settling observeSnapshot:snapshot(@"Loading",@0)];
 CHECK(![settling confirmExhaustion:YES atTime:10]);
 CHECK(![settling confirmExhaustion:YES atTime:10.5]);
 [settling observeSnapshot:snapshot(@"Loaded",@0)];
 CHECK(![settling confirmExhaustion:YES atTime:12]);
 CHECK(![settling confirmExhaustion:YES atTime:13]);
 CHECK([settling confirmExhaustion:YES atTime:14]);
 CHECK(![settling confirmExhaustion:NO atTime:15]);
 CHECK(![settling confirmExhaustion:YES atTime:16]);
 CHECK(![settling confirmExhaustion:YES atTime:16.1]);
 CHECK(![settling confirmExhaustion:YES atTime:16.2]);
 CHECK([settling confirmExhaustion:YES atTime:18]);
 FBExplorationGuard *passes=[FBExplorationGuard new]; NSDictionary *click=@{@"act":@"CLICK",@"pos":@[@0,@0,@100,@40]};
 [passes observeSnapshot:snapshot(@"Origin",@0)];
 for(int i=0;i<2;i++){[passes recordAction:click executed:YES reason:@""];[passes observeSnapshot:snapshot(@"Destination",@0)];[passes observeSnapshot:snapshot(@"Origin",@0)];}
 CHECK([passes exclusionsForCandidates:@[]].count==1);
 [passes recordAction:@{@"act":@"BACK"} executed:NO reason:@"not_hittable"];
 CHECK([passes beginNextPassForCandidates:@[@{@"bounds":click[@"pos"],@"clickable":@YES}] canGoBack:YES]==1);
 CHECK([passes exclusionsForCandidates:@[]].count==1); // rejection remains, useful navigation reopens
 CHECK([passes beginNextPassForCandidates:@[@{@"bounds":click[@"pos"],@"clickable":@YES}] canGoBack:YES]==0);
 [passes recordAction:click executed:YES reason:@""];[passes observeSnapshot:snapshot(@"Origin",@0)];
 [passes recordAction:click executed:YES reason:@""];[passes observeSnapshot:snapshot(@"Origin",@0)];
 CHECK([passes beginNextPassForCandidates:@[@{@"bounds":click[@"pos"],@"clickable":@YES}] canGoBack:YES]==0);CHECK([passes exclusionsForCandidates:@[]].count==2);
 FBExplorationGuard *contexts=[FBExplorationGuard new];
 NSMutableDictionary *keyboard=[snapshot(@"Search",@0) mutableCopy];keyboard[@"inputVisible"]=@YES;
 [contexts observeSnapshot:keyboard];NSString *inputFP=contexts.fingerprint;
 keyboard[@"inputVisible"]=@NO;[contexts observeSnapshot:keyboard];CHECK(![inputFP isEqual:contexts.fingerprint]);
 NSDictionary *transient=@{@"act":@"CLICK",@"pos":@[@0,@0,@100,@40]};
 [contexts recordAction:transient executed:NO reason:@"target_stale_or_not_hittable"];
 CHECK([contexts exclusionsForCandidates:@[]].count==0);
 [contexts recordAction:transient executed:NO reason:@"target_stale_or_not_hittable"];
 CHECK([contexts exclusionsForCandidates:@[]].count==1);
 FBExplorationGuard *cycles=[FBExplorationGuard new];
 for(int pass=0;pass<2;pass++){
  [cycles observeSnapshot:snapshot(@"A",@0)];
  for(int i=0;i<2;i++){[cycles recordAction:transient executed:YES reason:@""];[cycles observeSnapshot:snapshot(@"B",@0)];[cycles observeSnapshot:snapshot(@"A",@0)];}
  CHECK([cycles beginNextPassForCandidates:@[@{@"bounds":transient[@"pos"],@"clickable":@YES}] canGoBack:YES]==(pass==0 ? 1 : 0));
 }
 [cycles observeSnapshot:snapshot(@"Trapped",@0)];CHECK([cycles beginNextPassForCandidates:@[@{@"bounds":transient[@"pos"],@"clickable":@YES}] canGoBack:YES]==0);
 [cycles observeSnapshot:snapshot(@"A",@0)];CHECK([cycles beginNextPassForCandidates:@[@{@"bounds":transient[@"pos"],@"clickable":@YES}] canGoBack:YES]==1); // unrelated paths do not help this context
 NSArray *horizontal=@[@{@"bounds":@[@0,@98,@390,@138],@"scrollable":@YES,@"scrollDirections":@[@"SCROLL_LEFT_RIGHT",@"SCROLL_RIGHT_LEFT"]}];
 FBExplorationGuard *axes=[FBExplorationGuard new];[axes observeSnapshot:snapshot(@"Tabs",@0)];
 NSArray *axisEx=[axes exclusionsForCandidates:horizontal];CHECK(axisEx.count==2);
 CHECK([axisEx filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"act == %@",@"SCROLL_TOP_DOWN"]].count==1);
 FBExplorationGuard *intermittent=[FBExplorationGuard new];
 [intermittent observeSnapshot:snapshot(@"Origin",@0)];
 [intermittent recordAction:click executed:YES reason:@""];[intermittent observeSnapshot:snapshot(@"Origin",@0)];
 [intermittent recordAction:click executed:YES reason:@""];[intermittent observeSnapshot:snapshot(@"Destination",@0)];
 [intermittent observeSnapshot:snapshot(@"Origin",@0)];
 [intermittent recordAction:click executed:YES reason:@""];[intermittent observeSnapshot:snapshot(@"Origin",@0)];
 CHECK([intermittent exclusionsForCandidates:@[]].count==0); // successful transition separates two no-effects
 [intermittent recordAction:click executed:YES reason:@""];[intermittent observeSnapshot:snapshot(@"Origin",@0)];
 CHECK([intermittent exclusionsForCandidates:@[]].count==1);
 FBExplorationGuard *availability=[FBExplorationGuard new];[availability observeSnapshot:snapshot(@"Stable",@0)];
 NSArray *poolA=@[@{@"bounds":@[@0,@0,@100,@40],@"clickable":@YES}];
 NSArray *poolB=@[@{@"bounds":@[@1,@0,@101,@40],@"clickable":@YES}];
 NSString *contextA=[availability exhaustionContextForCandidates:poolA canGoBack:YES];
 NSString *contextB=[availability exhaustionContextForCandidates:poolB canGoBack:YES];
 CHECK(![contextA isEqual:contextB]);
 CHECK(![contextA isEqual:[availability exhaustionContextForCandidates:poolA canGoBack:NO]]);
 CHECK([[availability exhaustionContextForCandidates:@[poolA[0],poolB[0]] canGoBack:YES] isEqual:
        [availability exhaustionContextForCandidates:@[poolB[0],poolA[0]] canGoBack:YES]]);
 CHECK(![availability confirmExhaustion:YES atTime:0 context:contextA]);
 CHECK(![availability confirmExhaustion:YES atTime:1 context:contextA]);
 CHECK(![availability confirmExhaustion:YES atTime:2 context:contextB]);
 CHECK(![availability confirmExhaustion:YES atTime:3 context:contextB]);
 CHECK([availability confirmExhaustion:YES atTime:4 context:contextB]);
 FBExplorationGuard *orphan=[FBExplorationGuard new];[orphan observeSnapshot:snapshot(@"A",@0)];
 for(int i=0;i<2;i++){[orphan recordAction:click executed:YES reason:@""];[orphan observeSnapshot:snapshot(@"B",@0)];[orphan observeSnapshot:snapshot(@"A",@0)];}
 NSDictionary *replacement=@{@"act":@"CLICK",@"pos":@[@1,@0,@101,@40]};
 [orphan recordAction:replacement executed:NO reason:@"invalid_target"];
 [orphan recordAction:@{@"act":@"BACK"} executed:NO reason:@"unavailable"];
 NSArray *replacementPool=@[@{@"bounds":replacement[@"pos"],@"clickable":@YES}];
 CHECK(![orphan hasAvailableActionForCandidates:replacementPool canGoBack:YES]);
 CHECK([orphan beginNextPassForCandidates:replacementPool canGoBack:YES]==0); // disappeared old target is not an exit
 FBExplorationGuard *numeric=[FBExplorationGuard new];[numeric observeSnapshot:snapshot(@"1001",@0)];
 NSString *firstNumber=numeric.fingerprint;
 [numeric recordAction:click executed:NO reason:@"invalid_target"];
 [numeric observeSnapshot:snapshot(@"1002",@0)];
 CHECK(![firstNumber isEqual:numeric.fingerprint]);
 CHECK([numeric exclusionsForCandidates:@[]].count==0); // changed native action label is not the old exhausted context
 FBExplorationGuard *recovery=[FBExplorationGuard new];[recovery observeSnapshot:snapshot(@"Exhausted",@0)];
 [recovery recordAction:click executed:NO reason:@"rejected"];
 CHECK(![recovery confirmExhaustion:YES atTime:0]);
 CHECK(![recovery confirmExhaustion:YES atTime:1]);
 CHECK([recovery confirmExhaustion:YES atTime:2]);
 [recovery clearPending]; // Runner calls this before relaunch; same initial tree is possible.
 [recovery observeSnapshot:snapshot(@"Exhausted",@0)];
 CHECK(![recovery confirmExhaustion:YES atTime:10]);
 CHECK(![recovery confirmExhaustion:YES atTime:11]);
 CHECK([recovery confirmExhaustion:YES atTime:12]);
 CHECK(![recovery hasAvailableActionForCandidates:@[@{@"bounds":click[@"pos"],@"clickable":@YES}] canGoBack:NO]);
 // Reproduce a dense report page: distinct rejected targets are elimination
 // progress, not an engine repeatedly returning the same blocked operation.
 FBExplorationGuard *dense=[FBExplorationGuard new];[dense observeSnapshot:snapshot(@"Dense report",@0)];
 for(int i=0;i<40;i++) {
  NSDictionary *invalid=@{@"act":@"CLICK",@"pos":@[@0,@(i*5),@100,@(i*5+4)]};
  for(int retry=0;retry<2;retry++) {
   [dense recordAction:invalid executed:NO reason:@"target_stale_or_not_hittable"];
   CHECK(dense.stalledRejectionCount<15);
  }
 }
 CHECK(dense.blockedCount==40);
 NSDictionary *alreadyBlocked=@{@"act":@"CLICK",@"pos":@[@0,@0,@100,@4]};
 for(int i=0;i<15;i++) [dense recordAction:alreadyBlocked executed:NO reason:@"target_stale_or_not_hittable"];
 CHECK(dense.stalledRejectionCount==15); // broken selector stays bounded
 [dense recordAction:click executed:YES reason:@""];CHECK(dense.stalledRejectionCount==0);
 FBExplorationGuard *unsupported=[FBExplorationGuard new];[unsupported observeSnapshot:snapshot(@"Stable",@0)];
 for(int i=0;i<15;i++) [unsupported recordAction:@{@"act":@"NOP"} executed:NO reason:@"unsupported_action"];
 CHECK(unsupported.stalledRejectionCount==15);
 [unsupported clearPending];CHECK(unsupported.stalledRejectionCount==0);
 CHECK(dense.noEffectCount==0); // failed lookups never fabricate injected events
 NSLog(@"source guard tests passed");}return 0;}
