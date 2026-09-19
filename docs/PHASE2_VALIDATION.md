# Phase 2 验证记录

日期：2026-09-12。前置条件：用户确认 Phase 1 实机验收通过。

**Phase 2 代码、自动化对照、实机加载与中文底注页显示已完成。
未来分支保留 Experimental；尚不宣称所有实局行动轨迹已验证。**

## 自动化真值对照

执行 README 中的 Phase 2 命令，使用本机 Balatro 的 LuaJIT 2.0.5 DLL。
24 项测试通过：Phase 1 的 11 项 + Phase 2 的 13 项。
完整原始输出见 `phase2-test-results.txt`。

Phase 2 对照基于实际 Lovely dump 与 Steamodded 源函数：

- 私有 Lua 全局状态与真实 math RNG：4,000 次数值对照。
- pseudoseed / pseudorandom：2,500 次 per-key 更新与 resample 对照。
- 200 个种子 × 8 个 Ante：两个 Tag、单 Voucher、多 Voucher、
  small / big / boss 新路径和旧 Boss 路径。
- 解锁、requires、Shop Voucher 排除、Showman、pool flags：160 次。
- 多 Voucher、已 spawn 项和 from-tag key：80 次。
- forced / prescribed、空池 fallback、debuffed Showman、win_ante=1。
- 60 个种子各向前模拟 20 个 Ante，逐项对照 Tag、Boss、Voucher。
- 总计 **17,846 次生成器或结果项对照**；不等于 17,846 局完整实机游戏。
  单步生成器同时比较完整 per-key RNG 表，跨 Ante 比较结果项。

隔离与失效测试：

- 快照和嵌套数据修改不影响真实对象；预测后真实 RNG 序列不变。
- Ante UI 将真实 math RNG 替换为抛错哨兵仍可构建；游戏状态不变。
- 相同快照复用预测；改变已购 Voucher 后重新计算；禁用开关阻止预测。
- 自定义资格回调不执行；权重池关闭预测；异常模拟关闭私有 Lua 状态。
- 包装器让原函数只执行一次，保留 nil 与多个返回值。
- 注入 MISMATCH 后写入完整记录并关闭预测门禁。

测试用原型来自游戏 EXE，并应用本版 Steamodded 对原版 Blind 原型的转换。
无窗口环境的绘制对象、SMODS.showman 及诊断辅助函数有测试替身；
不能据此证明任何第三方回调、所有渲染场景或全部模组组合都兼容。

## 实机结果

通过正常桌面启动现有 Balatro，保留当前已安装模组组合。
日志 `lovely-2026.09.12-11.20.47.log` 确认 Oracle 0.2.0 正常加载。

- 已观察中文总览正常显示实际 seed / Ante / Blind / Stake / Deck。
- 已观察底注页在当前 Ante 2 时翻到预测 Ante 3：
  小盲注“充值标签”、大盲注“吊饰标签”、Boss“嘴巴”、Voucher“种子基金”。
  这张画面证明显示与分页可用，不单独证明未来实局一定如此。
- 原版按钮、分页、DynaText、字段背景、中文提示和返回按钮均正常显示。
  截图见 `screenshots/phase2-ante-zh.png`，实际画面 2560 × 1600。
- 玩家操作期间读取到 **13 条真实 MATCH**：Ante 1 为 6 条，Ante 2 为 7 条，
  覆盖 get_new_blind、get_next_tag_key、get_next_vouchers、get_next_voucher_key。
  这些比较同时涵盖返回值和真实 per-key RNG 表。
- 截止本次记录，没有 Oracle Lua 错误或 MISMATCH。原始加载日志存在
  JokerDisplay 与 MoreSpeed 各自 manifest.json 的 ignored metadata 报告，
  它们不是 Oracle 报错；没有修改这些模组。

相关 Oracle 日志摘录见 `phase2-live-log.txt`。
生成器实机核对不等同于每个提前展示的多 Ante 分支都逐步走完。
继续游戏时验证器会自动核对后续自然生成结果。

## 安装与后续范围

安装目录 `%APPDATA%/Balatro/Mods/Oracle` 已更新。
旧版备份在工作区 `work/backups/Oracle-before-phase2-20260912-112046`。
没有修改游戏 EXE、DLL、Steamodded 或其他模组；没有脚本改存档、seed、
金钱、卡牌或分数。实机运行期间的正常玩家操作会照常保存。

Phase 2 交付仅包含当前信息、底注预测与验证基础。
Shop / reroll / editions / stickers / Packs / Soul / draw order 按后续阶段实现。
本轮未验证手柄、英文实机画面、所有分辨率或长时间多模组压力场景。
