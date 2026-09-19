# 0.5.3：浮雕牌组持有 Double Tag 时无法预测补充包

报告：CZZXRBWB，白注，跳过 Ante 1 Big 的 Holographic Tag，进入 Ante 2
商店后补充包页显示当前状态不支持预测。

## 证据和原因

只读检查本机该局存档与日志，确认有 Double Tag；闪箔目标是 To the Moon，
18:57:11 的实际效果核对为 MATCH。尚未购买它时也会出现此问题。
原版 back.lua 在浮雕牌组击败 Boss 的 eval 回调获得 Double。

补充包 capture 共用 shop_snapshot.capture；它的旧规则用 next(G.GAME.tags)
拒绝任何持有标签的状态。该规则原为防止未模拟的标签改变商店生成，
却也拒绝了对开包候选牌没有作用的 Double。不是闪箔 edition RNG 发生偏移。

追踪本机 patched Card.open、Tag.apply_to_run 与 Steamodded context：
开包候选生成不调用 store_joker_create、store_joker_modify、voucher_add、
tag_add 和 Orbital 的 immediate 路径。补充包现在独立检查这些已审计原版
标签：Double、Uncommon、Rare、Foil、Holographic、Polychrome、Negative、
Voucher、Orbital。未适配标签、定义带 mod 标记或自定义 apply/set_ability
回调仍关闭预测，并显示更具体的本地化提示。

原有商店生成保护未放宽。Hallucination、自定义 Soul/Seal 等其他保护不变。
该修复不更改玩家卡牌、标签、存档、商店、真实 RNG 或种子。

## 回归与安装

运行 tests/run.py --tag-chains --fast；完整输出见 pack-tag-fix-test-results.txt。
此次 49 项测试通过（--fast 复用 Phase 2 fixture，未重跑其 13 项长循环）。
包括 379 个标签链场景及新增两项测试：

- CZZXRBWB / Ante 2 / 白注，以 Half Joker 和 Holographic To the Moon 建立
  相关状态；九种持有标签 × 五类包，共 45 个分支。使用本机原版生成函数
  比较包内卡牌及完整 keyed RNG，并核对标签不变、预览快照不变。
  这是针对原因的状态回归，不是完整重放玩家此前的每次操作。
- 未知标签、自定义标签回调、带 mod 标记的原版标签、Hallucination 保持
  拒绝状态；没有调用自定义回调来试探结果。

已更新本机模组并保留 config.lua；旧安装先备份。当前运行中的游戏需要
重启后加载 0.5.3，不需要重开这局。本次没有接管玩家对局进行操作，
修复后的实际页面仍需重启后确认。本轮不进入 Phase 6。
