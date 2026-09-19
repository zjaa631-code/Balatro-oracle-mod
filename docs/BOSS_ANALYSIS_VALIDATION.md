# 0.11.0 — Boss 影响分析

## 范围与真值

本阶段新增 prediction/bosses.lua，接受 detached 状态并通过 engine 的 boss_analysis adapter 输出结果。UI 只读取结果和原版 localization。当前安装基线为 Balatro 1.0.1o-FULL、Steamodded 26.829.0、Lovely 0.9.0、游戏自带 LuaJIT 2.0.5。

真值是当前 Lovely dump 的 Blind:debuff_card、Blind:debuff_hand、Blind:modify_hand、Card:set_debuff、Card:is_face、Card:get_id、Card:is_suit，以及 Steamodded 的 enhancement 属性查询、smeared_check 和 stone/wild 定义。tests/source_truth.py 运行时提取原版代码，记录其 SHA-256；原版代码不随发行包分发。

额外审阅 Blind:set_blind、new_round、Steamodded 的 Blind 回调包装器、Eye 初始化和 Wheel 本地化。Water 入场先按 round_resets.discards + round_bonus.discards 重置，再全部扣除；Needle 按 round_resets.hands - 1 扣除。当前已生效 Boss 不再显示一次入场扣除。

## 独立状态

快照包含本底注 Boss 或当前 Boss 的 disabled、hands、only_hand，当前牌型等级／基础分、金钱、弃牌重置、真实 playing_card ID、base、ability 和活跃 Joker。复制牌组及 RNG 后只在普通 Lua 数据上分析，不交换 G.GAME，不调用 live Card 方法，不调用 RNG。

原版 Stone Card 的 get_id 会调用 math.random 生成一个负数。分析只使用其“无点数”语义，避免读取人头牌属性时推进真实 math RNG；Pareidolia 仍可让 Stone 被当作人头牌。

## 自动核对

debug/boss_validator.lua 包装实际 debuff_card、debuff_hand 和 modify_hand。原回调只执行一次，保留返回值的数量及 nil。预测先在独立记录上完成，再比较实际削弱布尔值、牌型是否被禁止、等级、直接金钱或基础筹码／倍率。check=true 的原版试检查不会被误认为已经降级或扣钱。

连续相同验证输入以最多 64 个签名去重，避免每帧重复 MATCH 日志。不匹配复用统一日志：seed、ante、round、Boss、手牌请求、候选牌记录、Joker 条件、RNG before/after 和 expected/actual。原版自身 Stone 查询可能推进全局 math RNG；预测不得推进它，测试独立检查这一点。

本模块仅面向原版规则。未识别 Boss、自定义 rank/Joker/card 会拒绝预测。安装其他模组带来的回调覆盖不属于保证范围。

## 自动测试

新增 tests/bosses.lua：20 个 seed × 28 个 Boss × 4 组 Joker 条件 × 8 张牌，与原版函数实际执行后的削弱结果对比；覆盖基础／石头／万能／钢铁、既有 debuff、prevent_debuff、Vampire 过渡标记和 Boss 失效。牌型矩阵覆盖 check / 非 check、四种牌型（含隐藏牌型）、1–5 张、正负金钱、Eye/Mouth 历史、Arm 等级下限；Flint 覆盖小数及边界舍入。

另有独立状态与 RNG 不变、重复预览、Chicot、入场重置、验证故意篡改检测、原函数调用次数与 nil 返回值、UI 三视图缓存和隐藏牌型可见性测试。

```powershell
python tests/run.py --bosses --game-dir D:/steam/steamapps/common/Balatro --patched-dir "$env:APPDATA/Balatro/Mods/lovely/dump" --smods-dir path/to/Steamodded --report boss-report.json
```

开发时可用 --bosses-only。发行报告以 .txt 保存，避免 Steamodded 将测试报告识别为模组 manifest。

## 明确边界

28 个原版 Boss 都可显示原版规则，确定性削弱与条件分析由上述函数覆盖。随机目标（Hook / Wheel / Amber Acorn / Crimson Heart / Cerulean Bell）、翻面与后续抽牌链不在本阶段预测范围。受影响卡牌视图只统计扑克牌削弱，不意味着该 Boss 没有其他效果。

条件出牌不判断所选牌型是否由当前高亮牌实际组成，也不计算 Joker 连锁、最终得分或后续策略。未来 Boss 分析假设当前状态不变；实际进入后按真实状态重新读取。此版本不得表述为完整 Boss 事件链模拟器。
