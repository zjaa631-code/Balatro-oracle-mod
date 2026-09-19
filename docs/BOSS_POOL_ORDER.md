# 0.16.3：Boss 候选池顺序与预测停用

用户导出的 2026-09-19 诊断报告显示，底注 6 的 `get_new_blind` 预测为 `bl_psychic`，实际为 `bl_eye`；`boss` RNG 前后状态完全一致。因而偏差不在 RNG 推进，而在随机抽取所用数组的排列。

当前 Steamodded 的 `SMODS.create_blind_pool` 先遍历 `G.P_BLINDS`，把合格对象插入哈希表 `eligible_bosses`，最后再用 `pairs(eligible_bosses)` 把键放入数组。这个顺序不排序。Oracle 原先复制原型后，自己建立哈希表和数组；即使候选集合相同，重新分配哈希表也可能改变顺序，导致相同的 RNG 值选中另一张 Boss。

现在状态读取阶段先确认没有自定义 Blind 入池回调，再调用原版只读的 `SMODS.create_blind_pool` 捕获当前 small／big／boss 数组。它不使用 `pseudorandom`，也不改变游戏状态。预测阶段在深拷贝状态与独立 RNG 上抽取；只有底注、已选盲注、Boss 使用次数、禁用项仍与捕获时相同时才使用该数组。未来条件分支不复用当前数组，仍按实验性预测展示。自定义规则仍走“不支持”保护。

回归测试包括诊断报告所对应的底注 6、五个已用 Boss 和 `boss` RNG 值、200 个种子×8 底注的原版函数对照，并断言捕获不改变真实 `G.GAME` 和 RNG。
