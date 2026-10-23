#include "PortableEngine.h"
#include "json.hpp"
#include <cassert>
#include <fstream>
#include <iostream>
#include <sys/stat.h>
using nlohmann::json;
std::string xml(const char *id) {
 return std::string("<hierarchy><node index=\"0\" text=\"\" resource-id=\"")+id+"\" class=\"android.widget.Button\" package=\"test\" content-desc=\"\" clickable=\"true\" enabled=\"true\" scrollable=\"false\" long-clickable=\"false\" bounds=\"[10,20][110,70]\"/></hierarchy>";
}
int main(int argc, char **argv) {
 assert(argc == 2); std::string dir=argv[1];
 fastbot_ios::PortableEngine engine(dir,"test.app",123);
 std::ifstream early(dir+"/reuse.fbm"); assert(!early.good());
 bool rejected=false; try { engine.next("<hierarchy><node>","bad"); } catch (...) { rejected=true; }
 assert(rejected && engine.stateCount()==0);
 for (const auto &bad : {std::string(), std::string("<hierarchy>"),std::string("<hierarchy/>\0junk",18)}) {
  rejected=false;try { engine.next(bad,"bad"); }catch(...) {rejected=true;}
  assert(rejected && engine.stateCount()==0);
 }

 int clicks=0;
 for(int i=0;i<12;i++) {
  auto action=json::parse(engine.next(xml(i%2?"second":"first"),i%2?"page2":"page1"));
  assert(action.is_object() && action["act"].is_string());
  auto pos=action["pos"]; assert(pos.is_array() && pos.size()==4);
  for(auto &v:pos) assert(v.is_number_integer());
  if(action["act"]=="CLICK" || action["act"]=="LONG_CLICK") {
   ++clicks; assert(pos[0]==10 && pos[1]==20 && pos[2]==110 && pos[3]==70);
  }
 }
 assert(clicks>0); assert(engine.stateCount()>=2);
 engine.reset(); assert(engine.stateCount()==0);
 engine.next(xml("after-reset"),"reset-page"); assert(engine.stateCount()==1);
 engine.reset();
 auto mixed=xml("valid");
 auto at=mixed.find("</hierarchy>");
 mixed.insert(at,"<node index=\"1\" class=\"android.widget.EditText\" resource-id=\"disabled\" enabled=\"false\" clickable=\"true\" bounds=\"[200,200][300,250]\"/><node index=\"2\" class=\"android.widget.EditText\" resource-id=\"offscreen\" enabled=\"true\" clickable=\"false\" bounds=\"[400,400][500,450]\"/>");
 for(int i=0;i<40;++i) {
  auto action=json::parse(engine.next(mixed,"mixed-page"));
  if(action["act"]=="CLICK" || action["act"]=="LONG_CLICK") assert(action["pos"][0]==10);
 }
 engine.reset();
 std::string scroll="<hierarchy><node index=\"0\" class=\"android.widget.ScrollView\" resource-id=\"scroller\" enabled=\"true\" clickable=\"false\" scrollable=\"true\" bounds=\"[10,20][110,70]\"/></hierarchy>";
 json excluded=json::array();
 for(const auto &act:{"SCROLL_TOP_DOWN","SCROLL_BOTTOM_UP","SCROLL_LEFT_RIGHT","SCROLL_RIGHT_LEFT","BACK"}) excluded.push_back({{"act",act},{"pos",{10,20,110,70}}});
 excluded.back().erase("pos"); // BACK exclusions need no bounds.
 auto noAction=json::parse(engine.next(scroll,"scroll-page",excluded.dump()));
 assert(noAction["act"]=="NOP" && noAction["reason"]=="no_available_action");
 json onlyDown=excluded;
 onlyDown.erase(onlyDown.begin());
 for(int i=0;i<12;++i) {
  auto allowed=json::parse(engine.next(scroll,"scroll-page",onlyDown.dump()));
  assert(allowed["act"]=="SCROLL_TOP_DOWN");
 }
 json onlyUp=excluded; onlyUp.erase(onlyUp.begin()+1);
 assert(json::parse(engine.next(scroll,"scroll-page",onlyUp.dump()))["act"]=="SCROLL_BOTTOM_UP");
 // Lift exclusions on the same cached state, then exclude all again.
 auto lifted=json::parse(engine.next(scroll,"scroll-page")); assert(lifted["act"]!="NOP");
 assert(json::parse(engine.next(scroll,"scroll-page",excluded.dump()))["reason"]=="no_available_action");
 auto moved=scroll; moved.replace(moved.find("[10,20][110,70]"),15,"[30,40][130,90]");
 auto context=json::parse(engine.next(moved,"scroll-page",onlyDown.dump()));
 assert(context["act"]!="NOP" && context["pos"][0]==30);
 assert(engine.stateCount()==1);
 engine.reset();
 std::string duplicates="<hierarchy><node index=\"0\" class=\"android.widget.Button\" enabled=\"true\" clickable=\"true\" bounds=\"[10,20][110,70]\"/><node index=\"1\" class=\"android.widget.Button\" enabled=\"true\" clickable=\"true\" bounds=\"[200,20][300,70]\"/></hierarchy>";
 json blockFirst=json::array({{{"act","BACK"}},{{"act","CLICK"},{"pos",{10,20,110,70}}}});
 for(int i=0;i<8;++i) {
  auto peer=json::parse(engine.next(duplicates,"peers",blockFirst.dump()));
  assert(peer["act"]=="CLICK" && peer["pos"][0]==200);
 }
 json blockSecond=json::array({{{"act","BACK"}},{{"act","CLICK"},{"pos",{200,20,300,70}}}});
 auto restoredPeer=json::parse(engine.next(duplicates,"peers",blockSecond.dump()));
 assert(restoredPeer["act"]=="CLICK" && restoredPeer["pos"][0]==10);
 // Same abstraction, changed label and location; no old target may survive.
 std::string singleA="<hierarchy><node class=\"android.widget.Button\" text=\"Old\" enabled=\"true\" clickable=\"true\" bounds=\"[10,20][110,70]\"/></hierarchy>";
 std::string singleB="<hierarchy><node class=\"android.widget.Button\" text=\"New\" enabled=\"true\" clickable=\"true\" bounds=\"[341,53][382,97]\"/></hierarchy>";
 json backOnly=json::array({{{"act","BACK"}}});
 engine.next(singleA,"peers",backOnly.dump());
 for(int i=0;i<8;++i) {
  auto fresh=json::parse(engine.next(singleB,"peers",backOnly.dump()));
  assert(fresh["act"]=="CLICK" && fresh["pos"][0]==341 && fresh["pos"][1]==53);
 }
 engine.close(); engine.close();
 std::ifstream persisted(dir+"/reuse.fbm", std::ios::binary); assert(persisted.good());
 rejected=false; try {engine.next(xml("x"),"closed");} catch (...) {rejected=true;} assert(rejected);
 fastbot_ios::PortableEngine second(dir+"/isolated","other.app",321);
 assert(second.stateCount()==0); second.close();
 std::cout << "portable engine tests passed\n";
}
