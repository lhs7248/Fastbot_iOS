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
 NSLog(@"source guard tests passed");}return 0;}
