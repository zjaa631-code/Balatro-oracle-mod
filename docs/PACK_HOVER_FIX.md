# 0.13.3 补充包快捷预测状态修复

## 原因

截图中的预知页面可以显示天体包内容，悬浮提示却显示 oracle_pack_wait。prediction/quick.lua 之前用 SMODS.OPENED_BOOSTER 是否存在判断仍在开包。

当前安装的 Card:open 在开包时设置 SMODS.OPENED_BOOSTER，原版 G.FUNCS.end_consumeable 则移除 G.booster_pack 并恢复 PACK_INTERRUPT 中的游戏状态，没有清空该引用。它表示上次打开的对象，不能单独表示当前正在开包。因此开过一个包后，后续商店包一直被快捷预览门禁拦截。

## 修复

- 在公共补充包快照中用实际游戏状态及 G.booster_pack 面板生命周期判断 pack_open。
- 仅在实际开包期间读取 opened_pack 和 opened_cards，防止遗留引用与候选区域进入当前包显示。
- 悬浮提示使用相同快照的 pack_open；真正开包、关闭面板或商店重掷中继续等待。
- 不重置 SMODS.OPENED_BOOSTER，不修改任何真实对象、事件队列或 RNG。缓存继续按快照更新。

## 验证

提取当前安装的 end_consumeable 原版回调执行完整关闭事件队列，在 5 seeds × 5 类后续补充包中验证：引用确实保留、商店恢复后预知页面与悬浮结果一致、旧候选牌不混入、反复悬浮不推进 RNG 且复用缓存。同时覆盖六种实际开包状态、关闭面板、重掷等待及恢复后的刷新。

完整回归 133 组 PASS；快捷预览 7 组，包括 320 个塔罗实际使用场景、100 次补充包适配比较及 25 个原版关包生命周期场景。完整报告与代码哈希见 pack-hover-regression-report.txt，测试输出见 pack-hover-regression-results.txt。

保留其他功能和错误保护。更新后重启游戏继续原存档，由玩家进行实机验收。
