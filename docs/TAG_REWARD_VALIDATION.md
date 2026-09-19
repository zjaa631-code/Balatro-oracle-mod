# 0.8.1 — 跳过标签的补充包 / 充值奖励

## 原版调用链

真值来自当前安装的 Balatro 1.0.1o-FULL、Steamodded 26.829.0、Lovely 0.9.0。
直接检查 Lovely dump 的 Tag:apply_to_run、G.FUNCS.skip_blind、Card:open、Game:update_blind_select，
以及 Steamodded 的五类原版 Booster create_card overrides；复用 Oracle 已验证的 pack/create/RNG 模块。

skip_blind 先 add_tag（Double 排队复制），更新被跳过的盲注，然后触发 immediate，
最后只触发第一个 new_blind_choice 标签。因此 Big 的免费包仍使用**当前 Ante**，
不能沿用 Rare Tag「战胜 Boss 后进入下一 Ante 商店」的假设。

| 标签 | 原版奖励 |
| --- | --- |
| Standard / 标准 | p_standard_mega_1 |
| Charm / 吊饰 | p_arcana_mega_1 或 2，内容使用同一生成规则 |
| Meteor / 流星 | p_celestial_mega_1 或 2，内容使用同一生成规则 |
| Buffoon / 小丑 | p_buffoon_mega_1 |
| Ethereal / 空灵 | p_spectral_normal_1（普通包） |
| Top-up / 充值 | 最多 spawn_jokers 个 Common Joker，原版 create_card rarity=0 / key 后缀 top |

吊饰/流星的封面变体使用非 keyed 的 math.random，Oracle 不调用真实 math RNG 猜封面；
界面明确提示封面不确定，候选内容由当前 keyed RNG 和池生成。结果不延伸成完整后续游戏状态。

## 结果与边界

- 所有新预测只在私有 Lua RNG 与数据副本上执行。UI 只读取缓存结果。
- 充值每张生成后更新重复排除与拥有池，按真实 card_limit 处理 0/1/多个空位。
  保留当前 Showman、解锁、池耗尽回退、当前版本、原版区域相关的贴纸规则。
- 充值单次同步 callback 使用同一个栏位上限；新生成 Negative 的额外栏位计入后续 callback。
- 包内继续使用 Omen Globe、Telescope、当前可见/打过的牌型、Edition、seal、enhancement、Soul/Black Hole 路径。
- Soul 指向同一包生成完后立即使用的 Legendary；若先选其他牌，再按真实状态重新预测。
- Double 复制的多个包不能跳过玩家的选牌选择。只展示第一个确定的包；后续标签标明等待前包结算。
  持有的后续包标签在没有包打开时可直接悬浮，按当时真实状态预测，不重新取得或复制该标签。
- 未适配的原版 Hallucination 开包连锁仍明确拒绝，不静默显示忽略连锁的结果。未知自定义回调也保持原有保护。

## 自动核对

充值：原版 callback 前取副本，callback 后比较实际新增牌及完整 keyed RNG；
同时绑定跳过前的预期到原标签及每个 Double 副本，比较整条执行顺序。

标签免费包：复用 Card.open 前预测 / pack CardArea emplacement 后比较，额外绑定到
跳过前的标签实例。自动调用 use_card(from_tag) 不标记为玩家改变选择。
偏差记录完整输入、RNG 轨迹和 Expected / Actual，关闭失准预测；日志沿用
oracle-validation.log、oracle-tag-validation.log、oracle-tag-chain.log。

## 回归测试

```powershell
python tests/run.py --tag-rewards --stress --game-dir '<Balatro>' --patched-dir '<Mods/lovely/dump>' --smods-dir '<Steamodded>' --report '<workspace>/report.json'
```

开发时 --tag-rewards-only 保留旧模块测试夹具，仅运行本次专项及基础加载检查。

本次专项覆盖：

- 五种包标签 × 70 个 seed，交替 Small / Big，变化 Ante、Omen Globe、Telescope、贴纸和包大小。
- 100 个充值 seed，变化 0–5 栏位、已有 Common、小丑满栏、Double 副本。
- Double 包的选择边界及从后续真实状态继续预测。
- 完整候选 tooltip、保留原版正文、重复 hover 缓存和真实 RNG 不变。
- 充值 / 免费包从 pre-skip 到 callback / emplace 的 MATCH，以及注入错误时的 MISMATCH。
- Showman、Common 池耗尽、已有额外栏位。

这是执行提取的实际 Tag/skip/create_card/Booster 函数的本机对照，渲染和事件计时由测试夹具替代；
不是把几百次自动化比较描述为真人实机游玩。原版源码和存档不随包分发。
测试输出与 provenance 报告随包附于 tag-rewards-test-results.txt / tag-rewards-regression-report.txt。

本次完整回归结果：94 组测试通过，耗时 236 秒；其中奖励标签专项 7 组 / 453 个 native skip 场景，
原有 1,207 个消耗牌使用场景及商店、标签链、补充包、抽牌回归全部通过。

## 实机界面检查（2026-09-14）

已加载 0.8.1，在已有存档 4IMRVQG1、Ante 2 的 Big Blind 吊饰标签上确认原版 tooltip 正文保留，
追加五个候选：教皇、太阳、审判、倒吊人、命运之轮。标签链的大盲注页显示相同内容与五张
原版 Tarot 卡牌，窗口、刷新、返回完整可见。检查期间未跳过盲注或选择包内卡，实际开包验收仍由玩家完成。

启动和上述页面检查未见 Oracle Lua 错误。加载器有另外两个已安装模组 manifest.json 的 id 提示，
Oracle 的唯一 metadata 文件为 Oracle.json，本包测试报告均使用 .txt，不引入额外模组 manifest。
