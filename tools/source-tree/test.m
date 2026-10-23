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
 NSLog(@"source tree tests passed");
 } return 0; }
