# 0.10.0 — 单次消耗牌后的 shadow 牌组

输入是当前真实区域、实体 playing_card ID、sort_id、完整 ability/base、强化/版本/蜡封、永久加成和当前 RNG。输入只读取，不调用活体 Card 方法。预测先通过既有 consumable adapter 运行一次私有 RNG，再将直接结果应用到 detached 卡牌表、区域 ID 序列和全牌组。新牌保留独立身份；RNG after 随预测结果返回。

## 原版对照来源

- 当前 Lovely dump 的 Card:set_base、Card:set_ability、Card:use_consumeable；SMODS change_base / modify_rank 及各消耗牌 use。
- copy_card、create_playing_card：保留 ability/edition/seal；基础牌信息重建；生成牌进入手牌。
- CardArea:remove_card 从 deck.cards 尾端取牌。现有 deck 不会因为手牌变更而自动重建、洗牌或追加新牌。
- use_card / end_consumeable：最后一次选包会在后续事件中把手牌回收。此边界明确显示，未假定关包顺序。

所有原版代码只在本机测试临时目录中提取，不随发行包分发。

## 校验范围

实际使用后的既有 consumable 校验增加 deck 项目：实体 ID、牌心、点数数值、花色、强化、版本、蜡封、基础加成、永久加成，以及 deck/discard/play 顺序和 hand 成员。原始输入、使用前后 RNG、expected/actual 进入既有不匹配日志。非预测后续事件不纳入本阶段：动画/渲染字段、Joker 计分成长、关闭包后的区域回收。

在包内使用时，校验牌组属性与实体集合；关包会搬动区域，所以不做这一事件后的区域比较。正向手牌上限变化可能排队自动补牌，牌组视图明确拒绝该类结果；消耗牌直接效果预测保持可用。

## 测试

新增 tests/deck_state.lua：30 seeds × 24 消耗牌；King → Ace / Ace → 2；重复强化永久加成；Cryptid 新实体隔离；Immolate 删除及区域；篡改真实牌堆/永久加成的负向检测；原版 UI 的前后、区域、分页、列表和缓存。比较安装版本原版函数实际执行后的牌组与全部 keyed RNG。

运行完整回归：

```powershell
python tests/run.py --deck-state --stress --game-dir D:/steam/steamapps/common/Balatro --patched-dir "$env:APPDATA/Balatro/Mods/lovely/dump" --smods-dir path/to/Steamodded --report report.json
```

快速开发回归使用 --deck-state-only。发行报告使用 .txt 后缀，避免 Steamodded 把报告当作模组 manifest 扫描。

本阶段并非任意动作组合或下一盲注洗牌模拟。界面上的“待抽牌”是当前 shadow stack 的未来移出顺序；未假定玩家会打出、丢弃或使用哪一张牌。
