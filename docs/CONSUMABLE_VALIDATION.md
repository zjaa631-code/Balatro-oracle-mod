# 0.8.0 — Consumable Oracle

本次为用户新扩展路线的 Phase 1。已有功能及入口保留；不将后续 Joker Trigger、
完整牌组分支、Boss、Economy、What-if、Timeline 标为完成。

## 真值与架构

- Balatro 1.0.1o-FULL、Steamodded 26.829.0、Lovely 0.9.0、Windows LuaJIT 2.0.5。
- tests/source_truth.py 从本机 Lovely dump 提取消耗牌使用、复制/创建牌、Joker 加入/移除、
  洗牌、Boss 禁用函数；从当前 Steamodded 提取原版牌的 ownership overrides、概率和花色/点数工具。
- 运行时使用数据深拷贝和独立 Lua 状态，不替换 G.GAME，不临时推进真实 RNG，不调用 live create_card。
- engine 输入 snapshot，输出 result / RNG trace；UI 不调用 RNG。原有模块通过 adapter 接入；
  老页面原有调用接口暂时保留，后续逐步迁移，不宣称已完成全系统动作链模拟。
- 生成 Joker 继续复用已经验证的 pool、resample、rarity、edition、拥有牌排重、Showman 等逻辑。
  是否附加商店贴纸严格由原版生成区域决定，不向消耗牌生成的 Joker 强加商店贴纸。

## 覆盖范围

| 类别 | 当前直接效果 |
| --- | --- |
| 22 Tarot | 所有原版 Tarot。Wheel 成败/目标/版本，Judgement Joker，Emperor/High Priestess/Fool 生成牌；其余改牌/销毁/金钱 |
| 12 Planet | 从当前等级升级对应牌型；隐藏牌型名称走原版本地化 |
| 18 Spectral | 包括 Soul 与 Black Hole；复制、生成、销毁、版本、蜡封、点数/花色变化 |

Cryptid、Talisman、Aura、Death 等读取真实选中手牌，不虚构随机目标。
Black Hole 使用当前原版 +1 所有牌型的效果（含隐藏牌型），不误套 Orbital 的 +3。
Soul 无论从哪个可用来源进入使用操作都走 sou Legendary 生成；Wraith 原版直接生成 Rare，
普通 Cartomancer 的 Tarot 生成也不是 Soul 生成路径。

主要 RNG 调用：jud / sou / wra（交给原版同构 create 流）；emp / pri / fool；
wheel_of_fortune（判定、目标、版本按顺序）；ankh_choice；hex；ectoplasm；aura；
sigil / ouija；random_destroy；grim_create / familiar_create / incantation_create；spe_card；immolate。
这里是调用后缀或基础 key，真正的 per-key/Ante key 由对应生成函数构建，日志记录完整轨迹。
Immolate 私有 RNG 一次设种后连续 Fisher–Yates 抽取，不在每个 swap 前重新设种。

## 验证

专项对照覆盖 52 张牌 × 20 seeds，并补充 Wheel 的概率分子、Oops、成功/失败路径，
Ankh 的 sort_id 顺序、永恒、负片及 To Do List 复制时的额外 RNG，候选池、栏位、选牌变化，
包关闭时扑克牌移区、Joker 改变手牌上限、Negative 消耗牌的冻结栏位、Chicot 解除 Manacle。

专项共 10 组断言 / 1,207 个原版 use 场景。检查实际直接效果、全部 keyed RNG after、
预测前后输入/真实状态相等，以及真实 math RNG 未推进。额外验证 native UI 缓存与选牌刷新，
验证器注入 MATCH / MISMATCH，覆盖使用锁等待和停止不可靠预测。

完整 --consumables --stress 回归共 87 组测试通过（237 秒），包含所有既有模块；
最后的改牌 tooltip 数据修正后，重新运行 --consumables-only：11 组基础加载检查 +
10 组消耗牌专项再次通过。对应完整报告与最终 UI 专项报告分别保存，不混淆测试批次。

这是 **本机原版函数对照测试**：执行实际提取的 use 方法和关键 helper，渲染、音效、
动画事件通过测试替身运行。并非 1,207 次真人游戏录像；事件调度及所有 Joker 连锁效果
没有被测试替身完整复现。游戏内仍保留 Experimental，使用后自动核对用于发现真实状态偏差。

验证器在实际 use_consumeable 前取快照，原函数只调用一次；等待 use 锁及 STOP_USE 结束后，
按卡牌身份比较整副 playing_cards、Joker、消耗牌变化，避免包关闭返回牌堆被误判销毁。
SMODS 的手牌上限读取 base/mod 与卡牌贡献的结算值，避免 total_slots 刷新滞后误报。
输出到已有 oracle-validation.log；记录 seed、场景状态、完整预测/实际及 RNG trace。
MISMATCH 关闭预测门，防止继续展示已失准结果。

## 复现

```powershell
python tests/run.py --consumables --stress --game-dir '<Balatro>' --patched-dir '<Mods/lovely/dump>' --smods-dir '<Steamodded>' --report '<workspace>/report.json'
```

日常仅开发消耗牌时可用 --consumables-only（明确跳过旧模块测试），交付使用上面的完整命令。
成功日志随包提供 consumables-test-results.txt 和 consumables-regression-report.txt。
后者是 JSON 内容但使用 .txt 后缀，避免 Steamodded 将报告误当作模组 manifest。
原版提取源码、玩家存档和运行时私有数据不打包。

## 使用与边界

预知 → 页面组第三组 → 消耗牌。查看持有或包中牌，选项切换牌张，详情页显示原版预览卡或等级。
改牌详情展示结果，待扩展 Phase 3 再输出完整 successor deck 和基于它的下一步抽牌。
当前返回直接金钱/手牌上限变化，不等同于预测所有 Joker 内部计数、Boss 副作用和完整计分。
未形成合格目标、动画仍在进行或来源/规则不支持时不显示确定结果。

2026-09-14 已确认实机加载 Oracle 0.8.0 并进入现有对局的预知页面。
检测到玩家操作后停止鼠标输入，因此未完成新消耗牌页面的实机逐牌验收。
启动日志无 Oracle Lua 异常；存档加载有三条 Steamodded 商店 CardArea 尚未实例化信息，
随后游戏正常进入商店。新页面的有牌/选牌刷新与预览数据检查通过自动化测试，仍待玩家实机验收。
强化变化的预览从新 center config 构造说明并保留 perma_*；点数/花色变化从新 front 构造 base，
避免旧牌说明值覆盖新效果。Death 则保留被复制目标的完整 ability。
