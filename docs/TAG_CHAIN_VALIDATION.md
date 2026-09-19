# 0.5.2 Double / Voucher 标签链验证

本轮只扩展已验收的 0.5.1，尚未进入 Phase 6。实际环境为 Balatro
1.0.1o-FULL、Steamodded 26.829.0、Lovely 0.9.0、游戏 LuaJIT 2.0.5。

## 原版调用链与实现

`add_tag` 先对已有标签调用 `tag_add`，再加入新标签。Double 立即标记消耗，
在 `Tag:yep` 回调中以 `Tag(key)` 构造副本；Double 不复制 Double。
每个副本有独立身份，保持队列顺序。`prediction/tag_pipeline.lua` 负责
acquisition → expansion → immediate → shop → reroll → remaining state。

Orbital 的 `ability.orbital_hand` 通过原版 `G.orbital_hand` 传给副本，复制过程
不重新随机牌型。只有未绑定牌型的新 acquisition 才从实际可见池推进一次
`orbital`。原标签的实际 config 与副本的原型 config 分别处理。

Uncommon/Rare 沿用已验收的 create_card 与 uta/rta 流、稀有度池和 resample。
版本标签等待无版本且非 temp_edition 的合格 Joker。强制稀有度卡立即应用
版本，普通商品在队列回调应用版本；多标签不能统一简化成一次线性循环。

`Game:update_shop` 生成 Joker 栏位、正常 Voucher、补充包，再处理
`voucher_add`。每个 Voucher Tag 回调分别调用 `get_next_voucher_key(true)`，
使用 `Voucher_fromtag` / `_resampleN`，并在下次选择前将新券放入模拟商店。
保留 Showman、已用券、当前商店、used_jokers、requires、解锁和原版 fallback。
正常券 `.spawn=false` 不重新补发；生成额外券不更新 used_vouchers。

所有状态和 RNG 均在副本及独立 Lua 全局状态中推进。顺序 API 的
`acquisition_state` 用于继续取得标签；`resulting_shadow_state` 则已推进到
所显示商店/重掷结束，二者不可混用。再次取得标签时重新分配 stored 实例 ID。

## 自动回归

`tag-chain-test-results.txt`：完整 58 项回归通过，含原有 Phase 1–5、11 项
Tag 测试、5 项标签链测试。原有 Tag 对照包含 2,264 张商店卡牌比较。

随后对 UI 与连续 acquisition 身份处理的小修复运行
`tag-chain-followup-results.txt`（--fast 跳过已通过的 Phase 2 长循环）：
新增两项通过，共计 60 项不同测试覆盖；标签链共 379 个原版场景通过。

标签链测试使用本机 patched 原函数：Tag 构造器、add_tag、Tag:yep、
skip_blind、Game:update_shop 和 SMODS.add_voucher_to_shop。仅将画面、声音、
存档和动画外壳替换为测试桩，执行真实生成器及回调。测试事件队列按顺序执行，
不模拟动画时钟；真实动画交互仍需玩家验收。

- 附件要求的 15 类场景 × 20 seed：300 个场景。
- 六种 Joker 标签 × 12 seed：72 个场景，覆盖 2/3/4 栏位、贴纸和后续重掷。
- 正常券预选、已购券不补发、五种实际验证器组合：7 个场景。
- 另测 Orbital 原标签 +6、副本 +3；连续 Double acquisition；新 Orbital
  仅抽选一次；身份不冲突；持有 Double tooltip 与 Collection 区分。
- 比较全部商品、券序列、剩余标签、牌型等级、used_jokers、完整 keyed RNG。
- 重复预览比较真实快照，原有测试同时检查全局 math RNG 不变。

运行命令见 README。真值源码只提取到临时目录，不随模组发行。

## 实际验证与使用边界

开启「核对预测结果」后，跳过前保存链，原生 Double 回调绑定每个实际副本；
结算时核对 Expected / Actual、顺序和券列表。Voucher 回调还独立核对当前
真实状态下的结果及 keyed RNG。MISMATCH 写入 oracle-validation.log 并关闭
未来预测；中间购买、出售、用牌或出牌导致条件改变，保留预跳过期望并记录
CONDITION_CHANGED 到 oracle-tag-chain.log，单文件限制约 1 MiB。

所有延迟到商店的结果仍为 Experimental。假设跳过 Small 后完成 Big、跳过
Big 后完成 Boss；进入下一 Ante 时生成新正常券。这里没有模拟未来战斗、
再次跳过、消费卡牌或更改候选池的行为。相关流或池被这些操作改变后，旧分支
不再是确定结果。重掷分支假设不购买、出售和用牌，达到深度仍未结算则保留。
未知自定义回调/标签组合关闭预测。当前支持范围外的标签不冒充准确结果。

0.5.1 已获玩家实机验收；0.5.2 的全部标签交互验收仍待玩家实际游玩确认。

## 本次启动检查（2026-09-13 18:50）

已备份原安装并更新到 0.5.2，保留玩家 config.lua，运行时 Lua 文件哈希一致。
日志确认 0.5.2 加载；观察到原生 Oracle 八个页签和牌堆页正常显示。玩家已在
操作界面，因此未继续自动点击或推进对局，未宣称所有标签链已获实机验收。

`tag-chain-live-log.txt` 保留启动证据。一条 Orbital 尚未生成提示走安全拒绝
路径；三条商店 CardArea 载入消息也存在于 2026-09-09 的历史日志，早于本次
更新，来自 patched game.lua 的载入提示。此次没有观察到 Oracle Lua 崩溃。
