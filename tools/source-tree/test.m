#import <Foundation/Foundation.h>
#import "FBTreeAdapter.h"
static void check(BOOL condition, NSString *message) { if (!condition) { NSLog(@"FAIL: %@",message); exit(1); } }
static NSDictionary *node(NSString *kind, NSArray *frame, NSDictionary *extra) { NSMutableDictionary *n=[@{@"kind":kind,@"type":@1,@"frame":frame,@"enabled":@YES} mutableCopy]; [n addEntriesFromDictionary:extra?:@{}]; return n; }
int main(void) { @autoreleasepool {
 check([FBTreeAdapter pageFromSnapshot:nil bundleID:nil][@"nodeCount"]!=nil,@"nil safe");
 NSDictionary *root=node(@"other",@[@0,@0,@320,@640],@{@"children":@[
 node(@"button",@[@10,@10,@100,@40],@{@"identifier":@"go",@"label":@"Go"}),
 node(@"secureTextField",@[@10,@60,@200,@40],@{@"label":@"secret",@"value":@"secret"}),
 node(@"scrollView",@[@0,@120,@320,@500],nil),
 node(@"other",@[@10,@10,@20,@20],@{@"hittable":@YES}),
 node(@"button",@[@400,@0,@10,@10],nil),
 node(@"button",@[@0,@0,@10,@10],@{@"enabled":@NO})]});
 NSDictionary *page=[FBTreeAdapter pageFromSnapshot:root bundleID:@"test.app"];
 check([page[@"candidates"] count]==3,@"actionable candidates only");
 check(![page[@"xml"] containsString:@"secret"],@"secure redacted");
 check([page[@"xml"] containsString:@"android.widget.EditText"],@"editable mapping");
 NSMutableDictionary *changed=[root mutableCopy]; NSMutableArray *children=[root[@"children"] mutableCopy]; NSMutableDictionary *button=[children[0] mutableCopy]; button[@"label"]=@"Different"; children[0]=button; changed[@"children"]=children;
 check([page[@"pageKey"] isEqual:[FBTreeAdapter pageFromSnapshot:changed bundleID:@"test.app"][@"pageKey"]],@"stable labels");
 NSArray *c=page[@"candidates"];
 check([FBTreeAdapter targetForAction:@{@"act":@"CLICK",@"pos":@[@10,@10,@110,@50]} candidates:c]!=nil,@"click bounds");
 check([FBTreeAdapter targetForAction:@{@"act":@"CLICK",@"pos":@[@0,@120,@320,@620]} candidates:c]==nil,@"scroll not click");
 check([FBTreeAdapter targetForAction:@{@"act":@"CLICK"} candidates:c]==nil,@"missing bounds");
 check([FBTreeAdapter targetForAction:@{@"act":@"CLICK",@"pos":@[@10,@10,@110,@50]} candidates:@[c[0],c[0]]]==nil,@"ambiguous");
 check([FBTreeAdapter pageFromSnapshot:(id)@[] bundleID:nil][@"candidates"]!=nil,@"invalid root safe");
 check([FBTreeAdapter targetForAction:@{@"act":@"LONG_CLICK",@"pos":@[@10,@10,@110,@50]} candidates:c]==nil,@"unsupported action");
 check([FBTreeAdapter targetForAction:@{@"act":@"CLICK",@"pos":@[@"10",@10,@110,@50]} candidates:c]==nil,@"string number rejected");
 check([FBTreeAdapter targetForAction:@{@"act":@"CLICK",@"pos":@[@(-1),@10,@110,@50]} candidates:c]==nil,@"negative rejected");
 check([FBTreeAdapter targetForAction:@{@"act":@"SCROLL_TOP_DOWN",@"pos":@[@0,@120,@320,@620]} candidates:c]!=nil,@"scroll bounds");
 check([FBTreeAdapter targetForAction:@{@"act":@"CLICK",@"pos":@[@10.2,@10.2,@110.2,@50.2]} candidates:c]!=nil,@"float rounding");
 check([[FBTreeAdapter pageFromSnapshot:node(@"button",@[@0,@0,@0,@0],nil) bundleID:nil][@"candidates"] count]==0,@"zero sized root excluded");
 NSDictionary *clipped=[FBTreeAdapter pageFromSnapshot:node(@"other",@[@0,@0,@320,@640],@{@"children":@[node(@"scrollView",@[@0,@100,@320,@800],nil)]}) bundleID:@"app"][@"candidates"][0];
 check([FBTreeAdapter target:clipped matchesLiveBounds:@[@0,@100,@320,@900]],@"full live frame matches clipped candidate");
 check(![FBTreeAdapter target:clipped matchesLiveBounds:@[@100,@100,@420,@900]],@"moved live frame rejected");
 NSDictionary *rn=node(@"other",@[@0,@0,@390,@844],@{@"children":@[
 node(@"other",@[@12,@95,@49,@28],@{@"label":@"全部"}),
 node(@"other",@[@331,@100,@47,@18],@{@"label":@"筛选"}),
 node(@"staticText",@[@320,@57,@21,@20],@{@"label":@"\ue740",@"children":@[node(@"staticText",@[@320,@57,@21,@20],@{@"label":@"\ue740"})]}),
 node(@"other",@[@0,@131,@390,@679],@{@"label":@"Content"}),
 node(@"other",@[@357,@131,@30,@666],@{@"label":@"垂直滚动条, 1页"}),
 node(@"other",@[@0,@0,@30,@20],@{@"label":@"Disabled",@"enabled":@NO}),
 node(@"staticText",@[@10,@150,@200,@160],@{@"label":@"Long body"}),
 node(@"other",@[@10,@800,@200,@200],@{@"label":@"Clipped large body"})]});
 NSDictionary *rp=[FBTreeAdapter pageFromSnapshot:rn bundleID:@"app"];
 check([rp[@"candidates"] count]==3,@"RN labeled compact containers and duplicate glyph produce three candidates");
 NSDictionary *icon=[FBTreeAdapter targetForAction:@{@"act":@"CLICK",@"pos":@[@320,@57,@341,@77]} candidates:rp[@"candidates"]];
 check([icon[@"recognition"] isEqual:@"inferred_label"] && [icon[@"liveMatchCount"] integerValue]==2,@"duplicate icon counted for live validation");
 check([rp[@"xml"] componentsSeparatedByString:@"clickable=\"true\""].count==4,@"duplicates are not independently clickable in engine XML");
 NSDictionary *keyboardPage=[FBTreeAdapter pageFromSnapshot:node(@"other",@[@0,@0,@390,@844],@{@"children":@[node(@"keyboard",@[@0,@500,@390,@344],@{@"children":@[node(@"other",@[@10,@520,@30,@30],@{@"label":@"delete"}),node(@"button",@[@50,@520,@30,@30],@{@"label":@"emoji"})]})]}) bundleID:@"app"];
 check([keyboardPage[@"candidates"] count]==0,@"keyboard descendants must not become app exploration targets");
 NSDictionary *systemHost=node(@"other",@[@0,@476,@390,@368],@{@"children":@[
 node(@"other",@[@0,@476,@390,@368],@{@"identifier":@"inputView",@"children":@[node(@"cell",@[@10,@600,@40,@40],@{@"label":@"⌚️"})]}),
 node(@"other",@[@0,@476,@390,@77],@{@"identifier":@"SystemInputAssistantView",@"children":@[node(@"cell",@[@10,@508,@40,@45],@{@"label":@"是, 还是的是"})]})]});
 NSDictionary *hostPage=[FBTreeAdapter pageFromSnapshot:node(@"other",@[@0,@0,@390,@844],@{@"children":@[systemHost]}) bundleID:@"app"];
 check([hostPage[@"candidates"] count]==0,@"system input host includes suggestion and emoji siblings, not just Keyboard role");
 NSDictionary *wideRow=[FBTreeAdapter pageFromSnapshot:node(@"other",@[@0,@0,@390,@844],@{@"children":@[node(@"other",@[@0,@149,@390,@49],@{@"label":@"昵称"})]}) bundleID:@"app"];
 check([wideRow[@"candidates"] count]==1,@"full-width compact RN settings row is a candidate");
 NSDictionary *counterPage=[FBTreeAdapter pageFromSnapshot:node(@"other",@[@0,@0,@390,@844],@{@"children":@[node(@"staticText",@[@185,@38,@19,@19],@{@"label":@"1/1"})]}) bundleID:@"app"];
 check([counterPage[@"candidates"] count]==0,@"page counter is not a clickable control");
 check([counterPage[@"escapeGesture"] isEqual:@"preview_tap"],@"counter-only preview has bounded native dismissal");
 check([wideRow[@"escapeGesture"] isEqual:@"edge_back"],@"normal page uses standard iOS back gesture");
 NSDictionary *header=node(@"other",@[@0,@47,@390,@40],@{@"children":@[
 node(@"other",@[@0,@47,@40,@40],@{@"nativePath":@[@0,@0]}),
 node(@"staticText",@[@162,@55,@66,@23],@{@"label":@"个人信息"})]});
 NSDictionary *hp=[FBTreeAdapter pageFromSnapshot:node(@"other",@[@0,@0,@390,@844],@{@"children":@[header]}) bundleID:@"app"];
 NSDictionary *back=[FBTreeAdapter targetForAction:@{@"act":@"CLICK",@"pos":@[@0,@47,@40,@87]} candidates:hp[@"candidates"]];
 check([back[@"recognition"] isEqual:@"inferred_header_back"],@"unlabeled header back area is recognized from native sibling title");
 check([back[@"nativePath"] isEqual:@[@0,@0]],@"live ordinal path preserved for unlabeled target");
 NSDictionary *nestedWeb=node(@"webView",@[@0,@87,@390,@723],@{@"type":@58,@"children":@[node(@"webView",@[@0,@87,@390,@723],@{@"type":@58,@"children":@[node(@"staticText",@[@16,@181,@77,@19],@{@"label":@"生效日期："})]})]});
 NSDictionary *wp=[FBTreeAdapter pageFromSnapshot:node(@"other",@[@0,@0,@390,@844],@{@"children":@[nestedWeb]}) bundleID:@"app"];
 check([wp[@"candidates"] count]==1,@"nested same-bounds web views yield one scroll candidate, not body text clicks");
 NSDictionary *wt=[FBTreeAdapter targetForAction:@{@"act":@"SCROLL_BOTTOM_UP",@"pos":@[@0,@87,@390,@810]} candidates:wp[@"candidates"]];
 check(wt!=nil && [wt[@"liveMatchCount"] integerValue]==2,@"nested web scroll target has known live equivalence count");
 NSDictionary *tabs=[FBTreeAdapter pageFromSnapshot:node(@"other",@[@0,@0,@390,@844],@{@"children":@[node(@"scrollView",@[@0,@98,@390,@40],nil)]}) bundleID:@"app"];
 check([tabs[@"xml"] containsString:@"android.widget.HorizontalScrollView"],@"horizontal axis reaches the C++ action generator through XML class");
 check([tabs[@"candidates"][0][@"scrollDirections"] isEqual:@[@"SCROLL_LEFT_RIGHT",@"SCROLL_RIGHT_LEFT"]],@"short wide tab strip scrolls horizontally");
 check([FBTreeAdapter targetForAction:@{@"act":@"SCROLL_TOP_DOWN",@"pos":@[@0,@98,@390,@138]} candidates:tabs[@"candidates"]]==nil,@"wrong-axis swipe is rejected before dispatch");
 NSArray *viewport=@[@0,@0,@390,@844];
 check(![FBTreeAdapter inputVisibleForPrunedNode:node(@"statusBar",@[@0,@0,@390,@47],nil) viewport:viewport],@"status bar is not a visible keyboard");
 check([FBTreeAdapter inputVisibleForPrunedNode:node(@"keyboard",@[@0,@500,@390,@344],nil) viewport:viewport],@"visible keyboard recognized");
 check(![FBTreeAdapter inputVisibleForPrunedNode:node(@"keyboard",@[@0,@844,@390,@344],nil) viewport:viewport],@"offscreen keyboard is not visible");
 check(![FBTreeAdapter inputVisibleForPrunedNode:node(@"other",viewport,@{@"children":@[node(@"other",@[@0,@844,@390,@100],@{@"identifier":@"SystemInputAssistantView"})]}) viewport:viewport],@"input host presence alone does not prove assistant visible");
 NSDictionary *clippedTall=[FBTreeAdapter pageFromSnapshot:node(@"other",@[@0,@0,@390,@844],@{@"children":@[node(@"scrollView",@[@0,@800,@390,@600],nil)]}) bundleID:@"app"];
 check([clippedTall[@"candidates"][0][@"scrollDirections"] containsObject:@"SCROLL_TOP_DOWN"],@"clipped vertical scroller must not become a horizontal strip");
 NSDictionary *nativeChild=node(@"button",@[@10,@20,@100,@40],@{@"type":@9,@"label":@"Open"});
 NSDictionary *wrapper=node(@"other",@[@10,@20,@100,@40],@{@"type":@1,@"label":@"Open",@"children":@[nativeChild]});
 NSDictionary *preferred=[FBTreeAdapter pageFromSnapshot:node(@"other",@[@0,@0,@390,@844],@{@"children":@[wrapper]}) bundleID:@"app"];
 check([preferred[@"candidates"] count]==1 && [preferred[@"candidates"][0][@"type"] intValue]==9,@"native child button wins over inferred wrapper at the same bounds");
 NSUInteger budget=100;
 check([FBTreeAdapter consumeSnapshotNodeAtDepth:60 remaining:&budget] && budget==99,@"depth boundary remains valid");
 check(![FBTreeAdapter consumeSnapshotNodeAtDepth:61 remaining:&budget] && budget==0,@"truncated depth invalidates entire snapshot instead of accepting an incomplete candidate pool");
 check(![FBTreeAdapter consumeSnapshotNodeAtDepth:0 remaining:&budget],@"exhausted budget cannot underflow");
 NSDictionary *overlay=[FBTreeAdapter pageFromSnapshot:node(@"other",@[@0,@0,@390,@844],@{@"children":@[
 node(@"button",@[@10,@20,@100,@40],@{@"type":@9,@"identifier":@"background",@"label":@"Old"}),
 node(@"button",@[@10,@20,@100,@40],@{@"type":@9,@"identifier":@"foreground",@"label":@"New"})]}) bundleID:@"app"];
 check([overlay[@"candidates"] count]==2,@"same bounds do not discard distinct foreground/background identities");
 NSDictionary *overlapTarget=[FBTreeAdapter targetForAction:@{@"act":@"CLICK",@"pos":@[@10,@20,@110,@60]} candidates:overlay[@"candidates"]];
 check([overlapTarget[@"alternatives"] count]==2,@"overlap is retained for unique live hit testing instead of selecting a hidden first node");
 NSArray *overlapChoices=overlapTarget[@"alternatives"];
 NSDictionary *resolved=[FBTreeAdapter uniqueLiveTargetForCandidates:overlapChoices lookup:^NSDictionary *(NSDictionary *candidate){
   return [candidate[@"identifier"] isEqual:@"foreground"] ? @{@"complete":@YES,@"element":@"live-foreground"} : @{@"complete":@YES};
 }];
 check([resolved[@"candidate"][@"identifier"] isEqual:@"foreground"],@"unique foreground hit is selected with actual metadata");
 check([FBTreeAdapter uniqueLiveTargetForCandidates:overlapChoices lookup:^NSDictionary *(NSDictionary *candidate){return @{@"complete":@YES,@"element":@"hittable"};}]==nil,@"two distinct hittable targets remain ambiguous");
 check([FBTreeAdapter uniqueLiveTargetForCandidates:overlapChoices lookup:^NSDictionary *(NSDictionary *candidate){
   return [candidate[@"identifier"] isEqual:@"background"] ? @{@"complete":@NO} : @{@"complete":@YES,@"element":@"hittable"};
 }]==nil,@"an unfinished timed-out lookup cannot prove another target uniquely hittable");
 NSPredicate *identity=[FBTreeAdapter livePredicateForTarget:@{@"identifier":@"shared",@"label":@"New"}];
 check([identity evaluateWithObject:@{@"identifier":@"shared",@"label":@"New"}],@"same identity matches live query");
 check(![identity evaluateWithObject:@{@"identifier":@"shared",@"label":@"Old"}],@"shared identifier with another label must not inflate live match count");
 NSPredicate *secureIdentity=[FBTreeAdapter livePredicateForTarget:@{@"identifier":@"password",@"label":@"",@"secure":@YES}];
 check([secureIdentity evaluateWithObject:@{@"identifier":@"password",@"label":@"Password"}],@"redacted secure label is not compared with live text");
 NSPredicate *anonymousSecure=[FBTreeAdapter livePredicateForTarget:@{@"identifier":@"",@"label":@"",@"secure":@YES}];
 check([anonymousSecure evaluateWithObject:@{@"identifier":@"",@"label":@"Password"}],@"anonymous secure target uses bounded type and geometry lookup");
 NSDictionary *nearby=[FBTreeAdapter pageFromSnapshot:node(@"other",@[@0,@0,@390,@844],@{@"children":@[
 node(@"button",@[@10.1,@20,@100,@40],@{@"identifier":@"left"}),
 node(@"button",@[@11.1,@20,@100,@40],@{@"identifier":@"right"})]}) bundleID:@"app"];
 NSDictionary *rightTarget=[FBTreeAdapter targetForAction:@{@"act":@"CLICK",@"pos":@[@11,@20,@111,@60]} candidates:nearby[@"candidates"]];
 check([rightTarget[@"identifier"] isEqual:@"right"] && !rightTarget[@"alternatives"],@"distinct rounded core bounds must not be rejected as nearby ambiguity");
 check([FBTreeAdapter targetForAction:@{@"act":@"CLICK",@"pos":@[@11,@20,@111,@60]} candidates:@[nearby[@"candidates"][0]]]==nil,@"neighboring event cannot be rebound to the wrong candidate");
 NSMutableDictionary *diagnostic=[NSMutableDictionary dictionary];
 check([FBTreeAdapter uniqueLiveTargetForCandidates:overlapChoices lookup:^NSDictionary *(NSDictionary *candidate){
  return @{@"complete":@NO,@"reason":@"query_timeout",@"inspected":@32};
 } diagnostics:diagnostic]==nil,@"unfinished query rejected with diagnostic");
 check([diagnostic[@"reason"] isEqual:@"query_timeout"] && [diagnostic[@"lookups"] count]==1,@"incomplete query retains concrete reason and scan data");
 [diagnostic removeAllObjects];
 check([FBTreeAdapter uniqueLiveTargetForCandidates:overlapChoices lookup:^NSDictionary *(NSDictionary *candidate){
  return @{@"complete":@YES,@"element":@"hit",@"reason":@"matched"};
 } diagnostics:diagnostic]==nil,@"ambiguous query rejected with diagnostic");
 check([diagnostic[@"reason"] isEqual:@"ambiguous_hittable_targets"] && [NSJSONSerialization isValidJSONObject:diagnostic],@"ambiguity is serializable without live element objects");
 [diagnostic removeAllObjects];
 check([FBTreeAdapter uniqueLiveTargetForCandidates:overlapChoices lookup:^NSDictionary *(NSDictionary *candidate){
  return @{@"complete":@YES,@"reason":@"not_hittable",@"matches":@1};
 } diagnostics:diagnostic]==nil,@"no hittable target remains rejected");
 check([diagnostic[@"lookups"][0][@"reason"] isEqual:@"not_hittable"],@"no-hit lookup preserves detailed reason");
 NSLog(@"source tree tests passed");
 } return 0; }
