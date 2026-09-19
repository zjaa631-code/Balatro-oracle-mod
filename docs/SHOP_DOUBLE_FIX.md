# 0.5.4：Double Tag 误拦截商店预测

0.5.3 修复了补充包入口，但商店仍使用旧的“存在任何标签即 unsupported”
条件。浮雕牌组留下 Double Tag 时，商店只显示实际商品，没有重掷分页。

依据当前 patched Tag.apply_to_run：原版 Double 的 config.type 是 tag_add，
只有取得非 Double 标签时才消耗。create_card_for_shop 的创建与修改上下文
不会触发它。因此 shop_snapshot 现在允许原版、未覆盖行为的 Double。
自定义 mod/apply/set_ability 和改写 config.type 的情况仍拒绝；可能实际
改变商品的其他待结算标签继续使用已有标签链模块，不直接忽略它们。

此次修改同时覆盖 controller.shop_forecast 和自然商店生成验证器的快照
入口；原有补充包独立检查保留。没有修改真实 Tag、Card、商店或 RNG。

## 测试

运行原命令 --tag-chains --fast，51 项通过。Phase 2 的 13 项长循环未重复，
其余完整运行；输出见 shop-double-fix-test-results.txt。

新增两项测试，其中核心对照覆盖 36 个商店状态：

- 六个 seed（含 CZZXRBWB）、一个或两个真实原版 Double、2/3/4 栏位。
- 用原版 Tag、Game.update_shop 和 create_card_for_shop 建立真实测试商店。
- 购买一张商品后，当前页面保留空缺；重掷恢复完整栏位数。
- 调用实际 controller.shop_forecast，确认返回分页，而非只测底层生成器。
- 每种状态连续十次重掷，共 360 次重掷、1,080 张商品对照；比较卡牌属性
  和最终完整 keyed RNG。Double 始终未消耗；预览前后实时快照不变。
- 未知标签逻辑、自定义 Double 回调、改写类型及待结算 Rare 仍拒绝。

其余 379 个标签链场景和上一版的补充包回归全部通过。UI 继续使用现有
原版商品卡牌、重掷 option cycle 和 tooltip，本次不更改视觉布局。

安装先备份现有模组并保留 config.lua。运行中的游戏需重启后加载 0.5.4，
不需要重开存档。本次未自动操作玩家对局；重启后的实机页面待玩家确认。
仍未进入 Phase 6。
