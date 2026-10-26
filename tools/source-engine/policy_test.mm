#import <Foundation/Foundation.h>
#import "FBTreeAdapter.h"
#import "FBExplorationGuard.h"
#include "PortableEngine.h"
#include <iostream>
#include <cassert>
static NSDictionary *screen(NSString *name, double x=10) {
    return @{@"kind":@"other",@"type":@2,@"frame":@[@0,@0,@390,@844],@"children":@[
        @{@"kind":@"button",@"type":@9,@"identifier":name,@"label":name,@"frame":@[@(x),@20,@100,@40],@"enabled":@YES}]};
}
static NSDictionary *choose(fastbot_ios::PortableEngine &engine, FBExplorationGuard *guard, NSDictionary *page, BOOL back=YES) {
    NSMutableArray *excluded=[[guard exclusionsForCandidates:page[@"candidates"]] mutableCopy];
    if (!back) [excluded addObject:@{@"act":@"BACK"}];
    auto action=engine.next([page[@"xml"] UTF8String],[page[@"pageKey"] UTF8String],
        [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:excluded options:0 error:nil] encoding:NSUTF8StringEncoding].UTF8String);
    NSDictionary *result=[NSJSONSerialization JSONObjectWithData:[[NSString stringWithUTF8String:action.c_str()] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    for (NSDictionary *blocked in excluded) {
        if ([blocked[@"act"] isEqual:result[@"act"]])
            assert(![result[@"act"] isEqual:@"BACK"] && ![blocked[@"pos"] isEqual:result[@"pos"]]);
    }
    return result;
}
int main(int argc,char **argv) { @autoreleasepool {
    assert(argc==2 || argc==3);
    fastbot_ios::PortableEngine engine(argv[1],"test.policy",42);
    // Adapter -> guard axis exclusions -> real C++ selection -> adapter target validation.
    NSDictionary *tabs=@{@"kind":@"other",@"type":@2,@"frame":@[@0,@0,@390,@844],@"children":@[
        @{@"kind":@"scrollView",@"type":@46,@"frame":@[@0,@98,@390,@40],@"enabled":@YES}]};
    FBExplorationGuard *axes=[FBExplorationGuard new];[axes observeSnapshot:tabs];
    NSDictionary *tabPage=[FBTreeAdapter pageFromSnapshot:tabs bundleID:@"test.policy"];
    NSUInteger gestures=0;BOOL exhausted=NO;
    for(int i=0;i<10;i++) {
        NSDictionary *action=choose(engine,axes,tabPage,NO);
        if ([action[@"act"] isEqual:@"NOP"]) { assert([action[@"reason"] isEqual:@"no_available_action"]); exhausted=YES;break; }
        assert(([@[@"SCROLL_LEFT_RIGHT",@"SCROLL_RIGHT_LEFT"] containsObject:action[@"act"]]));
        assert([FBTreeAdapter targetForAction:action candidates:tabPage[@"candidates"]]);
        [axes recordAction:action executed:YES reason:@""];[axes observeSnapshot:tabs];gestures++;
    }
    assert(exhausted && gestures==4); // two no-effects per allowed direction; no endless scrolling
    engine.reset();
    // Finite A/B cycle, including BACK: one reopening after discovery, then exhaust.
    FBExplorationGuard *cycles=[FBExplorationGuard new];
    NSUInteger sent=0,passes=0;BOOL atA=YES;exhausted=NO;
    for(int i=0;i<50;i++) {
        NSDictionary *tree=screen(atA?@"A":@"B");[cycles observeSnapshot:tree];
        NSDictionary *page=[FBTreeAdapter pageFromSnapshot:tree bundleID:@"test.policy"];
        NSDictionary *action=choose(engine,cycles,page);
        if ([action[@"act"] isEqual:@"NOP"]) {
            assert([action[@"reason"] isEqual:@"no_available_action"]);
            if ([cycles beginNextPassForCandidates:page[@"candidates"] canGoBack:YES]) {passes++;continue;}
            exhausted=YES;break;
        }
        assert([action[@"act"] isEqual:@"BACK"] || [FBTreeAdapter targetForAction:action candidates:page[@"candidates"]]);
        [cycles recordAction:action executed:YES reason:@""];atA=!atA;
        [cycles observeSnapshot:screen(atA?@"A":@"B")];sent++;
    }
    assert(exhausted && passes==1 && sent<=16);
    engine.reset();
    // Same coarse tree fingerprint; a fresh rounded target must invalidate old exhaustion.
    FBExplorationGuard *fresh=[FBExplorationGuard new];
    NSDictionary *oldTree=screen(@"stable",.1);[fresh observeSnapshot:oldTree];
    NSString *fp=fresh.fingerprint;
    NSDictionary *oldPage=[FBTreeAdapter pageFromSnapshot:oldTree bundleID:@"test.policy"];
    NSDictionary *oldAction=choose(engine,fresh,oldPage,NO);
    [fresh recordAction:oldAction executed:NO reason:@"structural_rejection"];
    assert([choose(engine,fresh,oldPage,NO)[@"act"] isEqual:@"NOP"]);
    NSString *oldContext=[fresh exhaustionContextForCandidates:oldPage[@"candidates"] canGoBack:NO];
    NSDictionary *newTree=screen(@"stable",.9);[fresh observeSnapshot:newTree];assert([fp isEqual:fresh.fingerprint]);
    NSDictionary *newPage=[FBTreeAdapter pageFromSnapshot:newTree bundleID:@"test.policy"];
    assert(![oldContext isEqual:[fresh exhaustionContextForCandidates:newPage[@"candidates"] canGoBack:NO]]);
    NSDictionary *newAction=choose(engine,fresh,newPage,NO);
    assert([newAction[@"act"] isEqual:@"CLICK"] && [newAction[@"pos"][0] intValue]==1);
    assert([FBTreeAdapter targetForAction:newAction candidates:newPage[@"candidates"]]);
    engine.reset();
    // Native numeric labels change meaning even though the core abstracts digits.
    FBExplorationGuard *numbers=[FBExplorationGuard new];
    NSMutableDictionary *n1=[screen(@"number") mutableCopy];
    NSMutableDictionary *b1=[n1[@"children"][0] mutableCopy];b1[@"label"]=@"1001";n1[@"children"]=@[b1];
    [numbers observeSnapshot:n1];NSString *numberFP=numbers.fingerprint;
    NSDictionary *np1=[FBTreeAdapter pageFromSnapshot:n1 bundleID:@"test.policy"];
    NSDictionary *numberAction=choose(engine,numbers,np1,NO);
    [numbers recordAction:numberAction executed:NO reason:@"invalid_target"];
    assert([choose(engine,numbers,np1,NO)[@"act"] isEqual:@"NOP"]);
    NSMutableDictionary *n2=[n1 mutableCopy];NSMutableDictionary *b2=[b1 mutableCopy];b2[@"label"]=@"1002";n2[@"children"]=@[b2];
    [numbers observeSnapshot:n2];assert(![numberFP isEqual:numbers.fingerprint]);
    NSDictionary *np2=[FBTreeAdapter pageFromSnapshot:n2 bundleID:@"test.policy"];
    assert([choose(engine,numbers,np2,NO)[@"act"] isEqual:@"CLICK"]);
    engine.reset();
    // Coincident controls keep their identities; a hidden first peer must not hide an exit.
    NSMutableDictionary *overlap=[screen(@"background") mutableCopy];
    NSDictionary *front=screen(@"foreground")[@"children"][0];
    overlap[@"children"]=@[overlap[@"children"][0],front];
    FBExplorationGuard *overlay=[FBExplorationGuard new];[overlay observeSnapshot:overlap];
    NSDictionary *op=[FBTreeAdapter pageFromSnapshot:overlap bundleID:@"test.policy"];
    for(int i=0;i<2;i++) {
        NSDictionary *oa=choose(engine,overlay,op,NO);
        assert([oa[@"act"] isEqual:@"CLICK"]);
        NSDictionary *group=[FBTreeAdapter targetForAction:oa candidates:op[@"candidates"]];
        assert([group[@"alternatives"] count]==2);
        NSDictionary *resolved=[FBTreeAdapter uniqueLiveTargetForCandidates:group[@"alternatives"] lookup:^NSDictionary *(NSDictionary *candidate){
            return [candidate[@"identifier"] isEqual:@"foreground"] ? @{@"complete":@YES,@"element":@"front"} : @{@"complete":@YES};
        }];
        assert([resolved[@"candidate"][@"identifier"] isEqual:@"foreground"]);
        [overlay recordAction:oa executed:YES reason:@""];[overlay observeSnapshot:overlap];
    }
    assert([choose(engine,overlay,op,NO)[@"act"] isEqual:@"NOP"]); // one physical operation budget, not one budget per peer
    engine.reset();
    // Adjacent rounded regions must both remain selectable, then exhaust finitely.
    NSMutableDictionary *nearby=[screen(@"left",10.1) mutableCopy];
    nearby[@"children"]=@[nearby[@"children"][0],screen(@"right",11.1)[@"children"][0]];
    NSDictionary *nearPage=[FBTreeAdapter pageFromSnapshot:nearby bundleID:@"test.policy"];
    FBExplorationGuard *nearGuard=[FBExplorationGuard new];[nearGuard observeSnapshot:nearby];
    NSMutableSet *visited=[NSMutableSet set];NSUInteger nearSent=0;BOOL nearExhausted=NO;
    for(int i=0;i<8;i++) {
        NSDictionary *na=choose(engine,nearGuard,nearPage,NO);
        if ([na[@"act"] isEqual:@"NOP"]) {nearExhausted=YES;break;}
        assert([na[@"act"] isEqual:@"CLICK"]);
        NSDictionary *nt=[FBTreeAdapter targetForAction:na candidates:nearPage[@"candidates"]];
        assert(nt && !nt[@"alternatives"]);
        assert([na[@"pos"][0] intValue]==([nt[@"identifier"] isEqual:@"left"]?10:11));
        [visited addObject:nt[@"identifier"]];
        [nearGuard recordAction:na executed:YES reason:@""];[nearGuard observeSnapshot:nearby];nearSent++;
    }
    assert(visited.count==2 && nearSent==4 && nearExhausted);
    assert(![nearGuard hasAvailableActionForCandidates:nearPage[@"candidates"] canGoBack:NO]);
    assert([nearGuard beginNextPassForCandidates:nearPage[@"candidates"] canGoBack:NO]==0);
    engine.reset();
    // Replay a dense inaccessible page; filtering more than 15 candidates must
    // reach BACK, rather than ending before the remaining exit is considered.
    NSMutableArray *denseChildren=[NSMutableArray array];
    for(int i=0;i<40;i++) [denseChildren addObject:screen([NSString stringWithFormat:@"row-%d",i],i%10*30)[@"children"][0]];
    NSDictionary *denseTree=@{@"kind":@"other",@"type":@2,@"frame":@[@0,@0,@390,@844],@"children":denseChildren};
    if (argc==3) {
        NSDictionary *checkpoint=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]] options:0 error:nil];
        denseTree=checkpoint[@"snapshot"];assert(denseTree);
    }
    FBExplorationGuard *denseGuard=[FBExplorationGuard new];[denseGuard observeSnapshot:denseTree];
    NSDictionary *densePage=[FBTreeAdapter pageFromSnapshot:denseTree bundleID:@"test.policy"];
    NSUInteger attempts=0;BOOL filtered=NO;
    for(int i=0;i<2000;i++) {
        NSDictionary *da=choose(engine,denseGuard,densePage,NO);
        if ([da[@"act"] isEqual:@"NOP"]) {filtered=YES;break;}
        assert([FBTreeAdapter targetForAction:da candidates:densePage[@"candidates"]]);
        [denseGuard recordAction:da executed:NO reason:@"target_stale_or_not_hittable"];
        assert(denseGuard.stalledRejectionCount<15);attempts++;
    }
    assert(filtered && attempts>15);
    assert([denseGuard hasAvailableActionForCandidates:densePage[@"candidates"] canGoBack:YES]);
    NSDictionary *exit=choose(engine,denseGuard,densePage,YES);assert([exit[@"act"] isEqual:@"BACK"]);
    [denseGuard recordAction:exit executed:YES reason:@""];
    assert(denseGuard.stalledRejectionCount==0);
    std::cout << "dense page candidates=" << [densePage[@"candidates"] count] << " rejected attempts=" << attempts << " remaining exit=BACK\n";
    engine.close();
    std::cout << "adapter/guard/portable-engine policy integration tests passed\n";
}return 0;}
