#pragma once
#include <string>
#include <memory>
#include <mutex>
namespace fastbotx { class Model; }
namespace fastbot_ios {
// Internal-use source engine. Calls and destruction must be serialized.
class PortableEngine {
 std::shared_ptr<fastbotx::Model> model_;
 std::string storage_, bundle_; unsigned int seed_, initialSeed_;
public:
 PortableEngine(const std::string &storage, const std::string &bundle, unsigned int seed);
 ~PortableEngine();
 std::string next(const std::string &xml, const std::string &page, const std::string &excludedActions = "[]");
 size_t stateCount() const;
 void close();
 void reset();
 PortableEngine(const PortableEngine&)=delete;
 PortableEngine &operator=(const PortableEngine&)=delete;
};
}
