# 0.14.0 概率事件连续预测

## 使用

「预知 → 设置 → 概率事件预测深度」，或消耗牌／小丑触发页的同名控件，可选择 1、3、5、10、20 次，默认 5。结果每页 5 次，使用原版选项箭头翻页。设置由 Steamodded 持久化，升级保留旧设置并补齐新字段。

完整页展示所选深度。鼠标悬浮命运之轮、上述概率小丑、手牌中的幸运／玻璃牌，只展示下一次有效判定；调整完整页深度不增加悬浮条目，也不触发完整序列计算。牌堆上的牌继续显示抽牌序列。

## 范围与边界

- Wheel of Fortune：成功／失败、目标小丑、版本。连续使用保留已产生的版本，重新构建无版本候选池。假设每次已有一张可用命运之轮，获取卡牌的流程不在序列内。
- Space Joker、Bloodstone、Business Card、Reserved Parking：同类有效触发的成功／失败。具体触发条件在页面中显示；不是未来整手计分。
- 8 Ball、Hallucination：概率及生成的塔罗牌，生成后传播占用槽位、已拥有牌与候选池变化。槽位满时停止。
- Gros Michel、Cavendish、Glass：命中销毁判定即停止，不假设牌仍存在。显示的是销毁判定，不模拟其他来源阻止销毁或整轮结束过程。
- Lucky Card：每次有效触发按原版顺序处理 lucky_mult 与 lucky_money 两条流；两者可同时成功。
- Misprint：连续有效判定的倍率。

序列固定当前底注和当前概率修正，没有中途买卖、换底注、其他同流触发或卡牌获取。比如两个太空小丑或复制效果额外触发会消费同一条流，后续结果需按实际调用次数解读。香蕉并不模拟未来各轮全部行动，幻觉也不模拟打开补充包后全部选牌效果。发生真实操作后，下次查看按新快照重新计算。

这些边界在界面中标为 Experimental。其他已有目标选择／生成小丑保持单次预测，未伪装成完整路线模拟。

## 隔离与验证

prediction/events.lua 通过统一引擎进入一次独立 shadow 运行，顺序调用已验证的 consumables.apply 或 jokers.apply。各行保留自己的 RNG 后状态，不替换真实 G.GAME，不调用真实 RNG 后撤销。UI 不调用 RNG。签名缓存包含完整输入快照和深度，翻页不会重算。

tests/events.lua 将连续结果逐步与当前安装的原版 Lua 函数对照：每步概率结果、版本目标、生成卡、槽位停止以及完整 pseudorandom 状态；覆盖多 seed、不同概率修正、1／3／5／10／20 深度前缀、无目标和销毁边界，检查输入、真实状态、全局 math RNG 不变。另验证设置保存、分页、缓存和快捷悬浮仅调用单次适配器。既有 Expected/Actual 实机验证器继续观察实际事件。

2026-09-17 完整回归：140 组 PASS，耗时 210.870 秒，新增连续事件测试逐步比较了 5,089 次原版动作。环境为 Balatro 1.0.1o-FULL、Steamodded 26.829.0、Lovely 0.9.0，使用本机 lua51.dll。详见 event-depth-regression-report.txt（代码与原版提取片段的 SHA-256）和 event-depth-regression-results.txt。该结果是原版函数自动对照，不代表已完成游戏内视觉验收。

测试运行命令（路径按本机环境调整）：

```text
python tests/run.py --game-dir <Balatro> --bosses --card-insight --event-depth --patched-dir <Lovely dump> --smods-dir <Steamodded> --report <workspace report.json>
```

发布包只含测试代码和哈希报告，不包含游戏源码、玩家存档或私有日志。实机界面验收由玩家重启后完成。
