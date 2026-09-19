# Skip Tag 扩展验证 — 0.5.1 / 2026-09-13

Phase 5 已由玩家实机验收，本次是进入 Phase 6 前的增量功能。

## 真值与调用链

本机 Balatro 1.0.1o-FULL、Steamodded 26.829.0、Lovely 0.9.0。
源代码来自本机 Lovely dump 与已安装 Steamodded，测试临时提取，不随包发行。

- UI_definitions.lua 的盲注选项先按 G.GAME.hands 的 pairs 顺序构建池，使用
  SMODS.is_poker_hand_visible，再以 pseudoseed('orbital') 选择并存入
  G.GAME.orbital_choices[ante][blind]。
- Tag:set_ability 优先已有 orbital_hand / orbital_choices；缺少才随机生成。
  Oracle 在玩家能 hover 的标签上读取已生成值，不重复轮询 orbital RNG。
- 当前 SMODS 可见规则是 PokerHands 存在且 G.GAME.hands[hand].visible 为真，
  除非定义提供自定义 visible 函数。played 没有独立作为 Orbital 过滤条件。
  自定义函数未隔离适配时拒绝执行，不调用真实函数“试一次再撤销”。
- Orbital 实际调用 level_up_hand，再由 SMODS.upgrade_poker_hands 增加实际
  config.levels。当前等级来自 G.GAME.hands，包含此前所有升级结果。
- Uncommon 创建 create_card('Joker', shop, nil, 0.9, ..., 'uta')；Rare 为 1 / 'rta'。
  get_current_pool 将 0.9 映射到 2、1 映射到 3，不抽 rarity RNG。
  主要 key：Joker2uta<ante> / Joker3rta<ante>，以及 _resampleN、ediuta / edirta、
  etperpoll、ssjr、To Do List 的 to_do。
- Rare 先按实际已持有的不同 Rare key 计数；原版数量检查即使 Showman 在场也存在。
- 版本标签不创建牌。它修改无 edition、无 temp_edition 的第一张 Joker。
  普通商品的修改通过 Event 延迟执行；稀有度标签生成的商品立即尝试修改。
  模拟先完成实际生成顺序，再按原版延迟顺序处理普通商品。
- 库存栏位直接读取 G.GAME.shop.joker_max，测试覆盖 2 / 3 / 4 栏。

## 隔离与验证边界

预测复用独立 lua_State 的 RNG，全部输入先深拷贝。没有替换 G.GAME、
调用真实 RNG 后回滚、创建真实 Tag 或调用游戏 Card 构造器。
UI 复用已有 UI-only Card 和原版描述；不会新增普通调试窗口。

跨战斗的 Joker 结果是冻结相关条件的分支，必须显示 Experimental。
保存跳过前的完整输入、Expected、RNG trace、过滤池；到商店时比较输入条件，
结算后保留 Actual。CONDITION_CHANGED 不冒充 MATCH，也不当作模拟器偏移。
真实 Tag 效果调用仍独立做即时影子核对，原函数只执行一次。
诊断包含 seed、Ante、blind、tag、owned、候选池、重采样轨迹和 RNG 前后状态。

## 自动测试

完整回归日志 tag-test-results.txt：原有 42 项 + 首批标签 8 项，50 项通过。
最终补充回归 tag-final-tests.txt：复用 Phase 2 fixtures，Phase 1/3/4/5 全部通过，
标签共 11 项通过；Phase 2 的 13 项此前完整执行通过。

标签专项包含 2,264 张商店商品对照：100 个 seed 的六类标签、组合标签、
2/3/4 栏位、edition/stickers、Showman、Rare 已满、unlock、ban、pool gate、resample。
另有 60 个 seed 的 Orbital 原版选择与升级、三种秘密牌型、实际等级、
缓存与重复 hover、全局及 per-key RNG 隔离、预跳过/实际效果 MATCH、
CONDITION_CHANGED、NOPE、故意注入错误 Expected 的 MISMATCH 与关闭预测。
原版函数原样提取；渲染、声音、存档持久化与时间调度在测试中使用桩。

命令：

```powershell
python tests/run.py --game-dir 'D:/steam/steamapps/common/Balatro' --tags `
  --patched-dir "$env:APPDATA/Balatro/Mods/lovely/dump" `
  --smods-dir '<当前 Steamodded 目录>'
```

## 实机

0.5.1 已安装，旧版备份到 work/backups/Oracle-before-tags-20260913-130157，
保留用户 config.lua。13:02:22 启动日志确认加载 0.5.1。

13:03:25 实机日志记录 `MATCH TAG tag_foil effect Ante 3`，并记录
`TAG VALIDATION CONDITION_CHANGED tag_foil pre-skip`。Foil 实际效果与即时
影子预测吻合；跨跳过分支的输入条件已经改变，未冒充确定的预跳过 MATCH。
13:03:47 原有 Standard Mega Pack 核对仍为 MATCH。摘录见 tag-live-log.txt。

本轮观察到局内游戏正常运行，未对正在进行的操作发送额外点击。未完成所有
标签 tooltip / Ante 卡片的人工视觉检查，也未完成七类标签的玩家实机验收。
启动日志含其他模组元数据警告；不能把 Oracle 无异常表述为全环境无警告。
