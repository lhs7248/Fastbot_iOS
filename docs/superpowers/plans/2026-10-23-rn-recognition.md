# RN 控件识别补充

根因：公告页的全部、未读、已读、筛选为Other，有双层StaticText图标，原适配只允许标准控件，因此只剩ScrollView。

方案：从快照结构补充有标签、单行、宽度不超过屏幕、高度8–88pt的Other/StaticText推测候选；排除滚动条、禁用和不可见元素。相同位置点击候选仅保留一次。实时按type/label/id及原始bounds匹配，重复数量必须与快照一致且目标hittable。保持防空转屏蔽和两次恢复预算。记录recognition、targetLabel、inferredCandidateCount以便区分原生控件与推测点击。

验收：先复现RN容器和双层图标遗漏，回归测试修复；构建Runner，新基座运行2分钟，核对是否实际点击原先漏掉的入口及其前后界面变化、结束状态和无效循环上限。推测候选不等同可点击语义或业务覆盖。

真机反馈补充：iOS 26的输入候选词不是Keyboard子孙，而在SystemInputAssistantView与inputView宿主中，按该实际结构整段排除；临时只剩滚动控件的页面过渡不得马上判耗尽，添加同指纹3次且2秒稳定确认。测试先复现后实现；新增用例也覆盖屏外大容器裁剪后不能误判为小按钮。
