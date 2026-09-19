# 0.12.0 钩子预测及背面牌名称

原定下一阶段暂停。本版本只实现用户指定的钩子弃牌目标高亮和背面牌名称识别。

## 原版调用链

当前安装版本的 play_cards_from_highlighted 先将选中牌排队移往 G.play，再调用 Blind:press_play。钩子排队事件执行时，G.hand.cards 已不包含打出的牌。它复制剩余手牌，使用 pseudorandom_element(pool, pseudoseed('hook')) 最多选两张，每次按返回的原 pool index 删除，再强制弃掉高亮牌。

pseudorandom_element 对卡牌候选按 sort_id 排序；不直接按屏幕位置选取。本模块复制必要的实体 ID、sort_id、选中集合及 seed/hashed_seed/hook RNG，复用已校验的私有 RNG 后端。既不调用一次真实 RNG 后撤销，也不修改真实卡牌、区域或 RNG。

## 缓存与展示

prediction/hook.lua 经统一 engine 调用；hook_controller.lua 负责实时选牌快照与缓存。parse_highlighted 后即时同步；仅钩子有效并正在选牌时，每 0.1 秒进行小型签名检查以捕获外部牌序或 RNG 变化。签名不变时不运行预测。

ui/card_insight.lua 的 SMODS DrawStep 只读取目标集合，复用 voucher shader。前后朝向均可高亮；不添加 edition，不调用 juice_up 或任何 RNG。背面 hover 直接读取中心键、base 花色及点数，调用原版名称本地化和原版 popup；不翻牌、不调用可能推进 RNG 的完整活体卡牌描述。

关闭 Oracle 设置会关闭上述功能。钩子不可用或版本门禁失败时不显示虚构目标；背面名称是只读观察，不依赖预测门禁。所有功能按当前原版规则实现，第三方玩法修改不在准确性保证内。

## 自动核对

实际点击出牌前保存独立预期；Hook 的强制弃牌回调执行前，比较目标 playing_card 实体集合及 hook RNG 状态。只执行一次真实操作，保留原回调返回值。MISMATCH 复用统一日志，包含 seed、ante、round、输入手牌池、选择集合、hook trace、expected/actual，并关闭本次会话的后续预测。

## 回归

tests/card_insight.lua 提取真实 Blind:press_play 并执行其事件，使用真实 pseudoseed / pseudorandom_element：100 seed，手牌数量 1–12，已选数量 1–5，合计 5,000 场景，包含剩余 0、1、2 张、已推进和未初始化 hook 流以及反序 sort_id。

检查真实状态、输入快照、全局 math RNG 和 keyed RNG 不被预览改变；实际结果和 RNG 对齐；重复签名缓存；改选、RNG 推进、Boss 失效、无选择；native shader 调用及无 edition/facing 变化；背面小丑洗乱后的实体名称；正面 hover 沿用原逻辑；正常与故意扰动的实际核对。

```powershell
python tests/run.py --card-insight --fast --game-dir D:/steam/steamapps/common/Balatro --patched-dir "$env:APPDATA/Balatro/Mods/lovely/dump" --smods-dir path/to/Steamodded --report insight-report.json
```

加 --bosses 并移除 --fast 可运行此前模块完整回归。报告以 .txt 随包保存，原版提取源码不分发。

## 本次执行结果

2026-09-15：完整回归 122 组通过，其中新增 5 组、5,000 个原版 Hook 场景通过。完整报告见 card-insight-regression-report.txt 和 card-insight-regression-results.txt。

0.12.0 已安装，安装文件逐项哈希校验通过，原 config.lua 保留。实机启动进入正常界面；本次运行日志在 23:52:57 记录 MATCH Hook discard Ante 1，说明真实弃牌实体及 hook 流与预期吻合。该操作来自玩家当前对局，代理未代为出牌。高亮观感和背面名称的实机视觉验收仍需玩家确认；自动 UI 测试覆盖 shader 调用和名称解析，不替代实际视觉检查。
