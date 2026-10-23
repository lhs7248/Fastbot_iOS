#include "PortableEngine.h"
#include "Model.h"
#include "ModelReusableAgent.h"
#include "tinyxml2.h"
#include <stdexcept>
#include <sys/stat.h>
namespace { std::mutex engineMutex; }
namespace fastbot_ios {
PortableEngine::PortableEngine(const std::string &storage,const std::string &bundle,unsigned int seed):storage_(storage),bundle_(bundle),seed_(seed),initialSeed_(seed) {
 std::lock_guard<std::mutex> lock(engineMutex);
 if(storage.empty() || storage[0]!='/') throw std::invalid_argument("absolute sandbox storage required");
 struct stat info; if(stat(storage.c_str(),&info)!=0 || !S_ISDIR(info.st_mode)) throw std::invalid_argument("storage directory must exist");
 model_=fastbotx::Model::create();model_->setPackageName(bundle);
 model_->addAgent("",fastbotx::AlgorithmType::Reuse);
}
PortableEngine::~PortableEngine() { try {close();}catch(...){} }
std::string PortableEngine::next(const std::string &xml,const std::string &page,const std::string &excludedActions) {
 std::lock_guard<std::mutex> lock(engineMutex);
 if(!model_) throw std::runtime_error("engine is closed");
 tinyxml2::XMLDocument doc;
 if(xml.empty() || xml.find('\0')!=std::string::npos || doc.Parse(xml.data(),xml.size())!=tinyxml2::XML_SUCCESS || !doc.RootElement() || doc.RootElement()->NextSiblingElement()) throw std::invalid_argument("malformed UI XML");
 if(page.empty()) throw std::invalid_argument("page key is required");
 auto exclusions=nlohmann::json::parse(excludedActions);
 if(!exclusions.is_array()) throw std::invalid_argument("excluded actions must be an array");
 for(const auto &item:exclusions) {
  if(!item.is_object() || !item.count("act") || !item["act"].is_string()) throw std::invalid_argument("invalid excluded action");
  if(item["act"]!="BACK") {
   if(!item.count("pos") || !item["pos"].is_array() || item["pos"].size()!=4) throw std::invalid_argument("excluded action needs four bounds");
   for(const auto &coordinate:item["pos"]) if(!coordinate.is_number_integer()) throw std::invalid_argument("excluded bounds must be integers");
  }
 }
 std::srand(seed_); seed_=seed_*1664525u+1013904223u;
 auto element=fastbotx::Element::createFromXml(doc);
 std::vector<fastbotx::ElementPtr> freshElements{element};
 element->recursiveDoElements([&freshElements](const fastbotx::ElementPtr &node) { freshElements.push_back(node); });
 auto allowed=[&exclusions,&freshElements](const fastbotx::ActivityStateActionPtr &action) {
  if (!action->getEnabled() || !action->isValid()) return false;
  const auto &act=fastbotx::actName[action->getActionType()];
  for(const auto &item:exclusions) {
   if(item["act"]!=act) continue;
   if(action->isBack()) return false;
   auto target=action->getTarget();
   if(!target || !target->getBounds()) continue;
   const auto &bounds=*target->getBounds();
   if(item["pos"]==nlohmann::json::array({bounds.left,bounds.top,bounds.right,bounds.bottom})) return false;
  }
  if (action->isBack()) return true;
  auto target=action->getTarget();
  if (!target || !target->getBounds()) return false;
  const auto bounds=target->getBounds();
  for (const auto &node:freshElements) {
   const auto current=node->getBounds();
   if (!node->getEnable() || !current || current->isEmpty() || bounds->left!=current->left || bounds->top!=current->top || bounds->right!=current->right || bounds->bottom!=current->bottom) continue;
   switch (action->getActionType()) {
    case fastbotx::ActionType::CLICK: if (node->getClickable() || node->getCheckable()) return true; break;
    case fastbotx::ActionType::LONG_CLICK: if (node->getLongClickable()) return true; break;
    case fastbotx::ActionType::SCROLL_TOP_DOWN:
    case fastbotx::ActionType::SCROLL_BOTTOM_UP:
    case fastbotx::ActionType::SCROLL_LEFT_RIGHT:
    case fastbotx::ActionType::SCROLL_RIGHT_LEFT: if (node->getScrollable()) return true; break;
    default: break;
   }
  }
  return false;
 };
 auto result=model_->getOperateOpt(element,page,"",allowed)->toString();
 auto value=nlohmann::json::parse(result);
 const std::string act=value.value("act",std::string());
 if(act!="CLICK" && act!="LONG_CLICK" && act!="BACK" && act!="SCROLL_TOP_DOWN" && act!="SCROLL_BOTTOM_UP" && act!="SCROLL_LEFT_RIGHT" && act!="SCROLL_RIGHT_LEFT" && act!="NOP") { value["act"]="NOP";value["pos"]={0,0,0,0}; }
 if(value.value("name",std::string())=="no_available_action") value["reason"]="no_available_action";
 value["allowFuzzing"]=false;value["jAction"]="";value["extra0"]="";
 return value.dump();
}
size_t PortableEngine::stateCount() const {std::lock_guard<std::mutex> lock(engineMutex);return model_?model_->stateSize():0;}
void PortableEngine::reset() {
 std::lock_guard<std::mutex> lock(engineMutex);
 if(!model_) throw std::runtime_error("engine is closed");
 auto fresh=fastbotx::Model::create();fresh->setPackageName(bundle_);
 fresh->addAgent("",fastbotx::AlgorithmType::Reuse);
 model_=fresh;seed_=initialSeed_;
}
void PortableEngine::close() {
 std::lock_guard<std::mutex> lock(engineMutex);
 if(!model_)return;
 auto agent=std::dynamic_pointer_cast<fastbotx::ModelReusableAgent>(model_->getAgent(""));
 if(agent)agent->saveReuseModel(storage_+"/reuse.fbm");
 model_.reset();
}
}
