# 实现前源码审计

日期：2026-09-11。

## 环境与工作区

当前工作区最初只有 outputs/ 与 work/，没有现存 Oracle / Showman 仓库或 AGENTS.md。
实际游戏位于 D:/steam/steamapps/common/Balatro。
在获得存档目录权限后，确认实际 Mods 中无 Showman；已有
Steamodded、DVPreview、JokerDisplay、Always_Show_Seed、MoreSpeed 等。
没有修改这些模组。首轮无窗口测试使用原版 UI；Phase 1 后续已由用户确认实机通过。

Balatro.exe SHA256：
0D75FE164ACCF3312734D4B37AC98788DD15F0B8E4F9BB8B7F90C4E59DE93F47

Lovely version.dll SHA256：
CCFED59E4D245B7802C684FC86708E0A937F584D6E07D1ECC11E8EAE22F9FC1A

游戏内部 version.jkr：1.0.1o-FULL。
实际 Steamodded version.lua：26.829.0；实际 Lovely 日志：0.9.0。

## 原版真值位置

以下路径是从本机合法安装 EXE 提取的内部路径。原版文件仅保存在开发临时目录，
不包含在交付包中。

| 原版文件 | 位置与作用 |
| --- | --- |
| functions/misc_functions.lua | pseudoshuffle:206、pseudorandom_element:253、pseudohash:279、pseudoseed:298、pseudorandom:315 |
| functions/common_events.lua | Voucher:1901、Tag:1914、get_pack:1942 附近、get_current_pool:1963、create_card:2082、get_new_boss:2338 |
| functions/UI_definitions.lua | create_card_for_shop:742、create_tabs:2047、create_UIBox_options:2208、generic_options:6308、UIBox_button:6376 |
| functions/button_callbacks.lua | overlay_menu:1328、exit_overlay_menu:1359、options:1387 |
| cardarea.lua | shuffle:572、draw_card_from:592；实际抽取还需追踪 remove_card 的尾部选择和 discarded_only |
| card.lua | Card:init、set_ability、open、use_consumeable 是后续卡牌显示副作用与补充包预测审计入口 |
| game.lua | 初始化 pseudorandom、round_resets、blind_choices、blind_tags；商店创建、Ante 转换 |

后续必须同时核对本机 Steamodded 的 Lovely patched dump；原版函数名或版本
相同不能证明其运行时代码与候选池未被其他模组改变。

## Showman 阅读范围与结论

通过作者仓库完整读取所有 Lua 实现、UI、加载补丁及 README / PLAN：
[12problems/Showman](https://github.com/12problems/Showman)。

Showman_seek.lua 的 Git blob：
0748e9838feda1e5b61c4b54e6929f1edb35e465

Showman_UI.lua 的 Git blob：
bf9adaa6bd20ee2f4a2490b4ff19e4f708498ce2

没有把 Showman、其 nativefs 或其他项目的代码打包进 Oracle。

可参考的思路：原版菜单集成、原版 CardArea 呈现、按页新建并销毁 UI 对象、
按 key 的随机状态、保留 UNAVAILABLE 候选位置与 resample 次序。

不能直接复用的实现：

1. Showman 的 RNG 调用全局 math.randomseed / math.random，不满足独立模拟要求。
2. get_current_pool 使用真实 G.ARGS.TEMP_POOL，探测调用也会动到共享池。
3. create_pseudocard_for_options 给真实 G.GAME.spectral_rate 赋默认值；
   reset_idol_card / reset_mail_rank / reset_ancient_card / reset_castle_card
   辅助函数写真实 current_round，不能作为只读模拟模块使用。
4. 部分池权重路径调用真实 SMODS.poll_object，不能假设没有 RNG 副作用。
5. 包内简化实现不能视作完整 Soul / Black Hole / Telescope / 牌面 / sticker 真值。
6. Showman 关于“原版不追加 Ante，只有 Steamodded 追加”的注释不适用于本机：
   本机原版 common_events.lua:2051 已返回带非 Legendary Ante 后缀的 pool key。
7. Showman README 自述其商店结果目前与实机有不匹配；不能将之当回归基准。

Blueprint、The Soul 与 Seed Searcher 可在后续阶段用于交叉检查。本阶段未移植这些
项目，也不声称已经完整审阅其实现。

## 复用与重新实现

Phase 1 直接调用原版 generic_options / tabs / UIBox_button / DynaText /
create_toggle / overlay_menu / localize。没有新字体、位图、HTML 或原生系统控件。

重新实现：只读 scalar snapshot、Blind 场景判定、语义化菜单插入、模块注册、
Steamodded 本地化、兼容性状态与测试。

Phase 2 计划新增：独立 RNG 后端、必要游戏模拟 DTO、独立池构建、准确性门禁与
预期/实际日志。严禁 setfenv 活体函数、替换 G.GAME 或“真实执行后恢复”。
LuaJIT math.random 与 love.math.RandomGenerator 不能未经对照证明就认为等价。
未按 key 重新播种的分支若缺少可复制的 RNG 状态，必须报告 Unsupported /
Experimental，不能补一个猜测值。

未来结果以当前快照和明确动作分支为条件。购买、跳过、使用消耗牌、重复 Soul、
reroll、Boss 重掷等都会改变后续状态，不能把不同选择生成的预测拼成一条必然序列。

## Phase 2 实际实现审计（2026-09-12）

真值进一步采用实际 `Mods/lovely/dump/functions` 和当前安装 Steamodded 源码，
测试自动提取源函数，未用模拟器自身作为 Expected。

- `pseudoseed` 的暂停分支调用全局 RNG；Oracle 模拟的是恢复游戏后的正常分支。
  保留 per-key 初始化、13 位小数更新、seed hash、resample 后缀与槽位。
- `simulation/backend.lua` 通过游戏 LuaJIT FFI 创建独立 Lua 全局状态，
  不用 `love.math.RandomGenerator` 替代，不修改活体 Lua 函数环境。
- `SMODS.get_new_blind` / `create_blind_pool` 才是本版本通常使用的路径；
  `get_new_boss` 仍单独支持，以便核对旧接口。两者筛选与选择顺序有区别。
- SMODS Boss 池由 hash 变为未排序数组。快照记录真实 `G.P_BLINDS`
  遍历顺序，重建候选表，保留删除/插入拓扑；不能粗暴排序后采样。
- `bosses_used` 新版本按 small / big / boss 分组；真实转发 metatable
  不带进模拟，而是复制原始计数表。兼顾最少出现次数、允许重复、showdown。
- `SMODS.get_next_vouchers` 一次建池后生成多个券，保留 `.spawn`、槽位、
  去重重采样；from-tag 使用 `Voucher_fromtag`，不是默认 Ante key。
- Tag / Voucher 保留 UNAVAILABLE 槽位；处理解锁、requires、Showman、
  used_jokers、已购券、当前商店券、banned_keys、pool flags 和空池 fallback。
- 自定义 `in_pool`、权重和资格回调不调用，明确关闭相关预测。
- 跨 Ante 源流程：Boss 胜利增 Ante → 生成 Voucher → cash_out 生成两个 Tag
  → reset_blinds / SMODS.reset_blind_choices。模拟按此顺序推进副本。
- 验证包装器只在玩家本来就要生成时运行；保持原函数只执行一次及全部返回值。
  比较生成结果和完整 RNG 表。UI 构建不调用这些真实生成器。

没有移植 Showman 或其他整个项目；新增模块按上述本机行为独立编写。

## Phase 3–5 实际实现审计

- 商店以当前 SMODS rarity 权重和原版候选池资格为真值；保留 UNAVAILABLE
  占位与 resample。edition 使用当前四种原版 SMODS edition 权重和原版遍历顺序。
- Shop/Pack 的 Eternal/Perishable/Rental 使用各自 key；To Do List 额外推进 to_do。
- SMODS 接管 Standard Pack 后顺序为 edition → seal → stdset → create_card，
  不使用旧版 Card.open 中不同的生成顺序。Soul 继续执行 Legendary Joker4 池及 edisou。
- 验证器在自然开包时预测所有候选牌，全部 emplace 后比较；Soul 单独核对。
- 描述克隆全新函数对象并使用私有环境，不改变活体函数的 setfenv；SMODS 旧版
  tooltip 临时槽使用独立空表，避免复制函数或污染共享 compat 表。
- 当前牌序以实际 patched CardArea.remove_card 和 draw_card_from 为准，末尾先抽。
  原版 emplace 到 deck 时插入数组开头（底部）。不把 discard 或 hand 擅自混回 deck。
- change_shop_size 更新 G.GAME.shop.joker_max，并立即填满当前商店缺口。
  Oracle 使用更改完成后的真实上限及 RNG；不从持券数量重复增加已更新的上限。
- 从 HUD 进入面板须先暂停再构造 DynaText，否则文字会绑定停止推进的游戏计时器。
# Skip Tag 扩展（2026-09-13）

已完整追踪本机 patched tag.lua 的 set_ability、apply_to_run、generate_UI、
get_uibox_table，以及 skip_blind、create_card_for_shop、get_current_pool、
create_card、SMODS.is_poker_hand_visible、level_up_hand / upgrade_poker_hands。
新增 prediction/tags.lua 和 debug/tag_validator.lua；未复制现有开源项目整体。
具体 RNG key、Orbital 可见池规则、延迟修改顺序及实验性边界见 TAG_VALIDATION.md。

## 0.5.2 标签链审计

补读本机 Tag.init/yep/remove/remove_from_game、add_tag、完整 Game:update_shop、
SMODS.add_voucher_to_shop 与 skip_blind 的事件顺序。Double 构造新 Tag，
Orbital 通过 G.orbital_hand 传递绑定牌型；Voucher 逐回调更新物理商店候选池。
新增独立 tag_pipeline 和 tag_chain_validator，UI 只消费标准结果。
具体规则、原版函数对照和限制见 TAG_CHAIN_VALIDATION.md。
