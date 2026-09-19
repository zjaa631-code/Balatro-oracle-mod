# 0.13.1 投资标签误拦截修复

## 定位

用户本局只读存档中的 seed 为 HTS25CEP、Ante 1、白注，持有 tag_investment。日志显示新一局正常读取 RNG，商店预测却被 unsupported 门禁拦截。

simulation/shop_snapshot.lua 原先仅放行持有的 Double Tag；prediction/packs.lua 的标签名单也没有 Investment。因此不参与商店或开包生成的投资标签，被同时误判为会改变生成规则的标签。这不是蓝色牌组、白注或 seed 本身不受支持。

## 原版依据与修复

审阅当前安装版本的 Tag:apply_to_run：Investment 仅在 eval 且 last_blind.boss 为真时结算；Juggle 仅在 round_start_bonus 改变手牌上限；Double 仅在 tag_add 复制后取得的标签。三者均不响应商店的 store_joker_create / store_joker_modify 或补充包生成。

新增共用 inert_tag 检查，用于商店和补充包门禁。检查实际 tag key、原型的原版触发类型、实例的触发类型，以及 mod / apply / set_ability 回调；不按标签名称模糊判断，也不删除、消费或提前结算真实标签。未知或改写过的行为继续拒绝预测。其他会改变商品的标签仍走既有独立模拟或保护流程。

## 验证

- 20 seeds × 投资／杂耍／双倍，覆盖 2、3、4 栏商店与连续三次 reroll，使用当前原版 Tag:apply_to_run 与商品生成函数比对。
- 本地专项测试额外读取用户存档的 RNG 副本作为其中的输入。测试对象池由既有原版 fixture 建立，不把它宣称为整份活体存档的完整重放。真实存档没有被修改，也不放入发布包。
- 每种补充包加入持有投资和杂耍标签的原版候选比较，检查标签未被预测或生成消费。
- 验证投资标签仍在 Boss 结算返回原版 25 美元奖励；改变触发类型和自定义回调仍被拒绝。
- 保留真实 RNG 和 shadow state 隔离，继续运行全部既有回归。

完整回归结果：129 组 PASS（202.305 秒），包含商店、补充包、标签、消耗牌、Joker、牌组修改、Boss、钩子与快捷悬浮预览。详细输出见 inert-tag-regression-results.txt，源码哈希与运行环境见 inert-tag-regression-report.txt。

更新后需重启游戏再继续原存档；无需重开这局。实机验收由玩家执行。
