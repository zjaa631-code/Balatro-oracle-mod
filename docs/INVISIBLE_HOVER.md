# 0.14.1 隐形小丑快捷预览

仅扩展持有小丑的原版 hover 说明，不新增分页或连续模拟。预知部分显示当前出售时的复制目标和生成牌，保留名称本地化、版本及贴纸信息。负片目标的复制品不带负片。未达到回合条件、栏位限制、无其他小丑或被削弱时，由现有预测适配器返回相应状态。

复用 prediction/quick.lua 的单次 Joker 适配器和快照缓存，以及 prediction/jokers.lua 的 shadow 复制逻辑。商店、收藏、Oracle 预览卡不添加出售预测。悬浮不修改真实状态或 RNG，不受 event_depth 设置影响。改变持有牌、invis_rounds 或对应 RNG 后，下次悬浮重新预测。

核对本机 patched Card:sell_card 与 calculate_joker：selling_self 判定在源牌溶解之前发生；达到 ability.extra 所需回合且栏位允许时，排除自己构建候选池，通过 pseudoseed('invisible') 选择目标，调用 copy_card 并剥除负片，复制出的隐形小丑回合计数归零。

2026-09-17 相关回归 31 组 PASS（67.190 秒）。新增 60 个 seed，改变目标版本和候选顺序，比较 hover 结果、原版实际生成牌和最终 RNG；检查重复悬浮缓存、深度独立、回合就绪、无目标和显示区域限制。同时运行既有快捷预览、小丑触发和连续概率深度测试：1,780 个原版小丑场景、5,089 次连续原版动作，以及快捷消耗牌／补充包对照。

命令：tests/run.py --jokers-only --event-depth，加本机 game-dir、patched-dir、smods-dir 参数。报告为 invisible-hover-regression-report.txt 和 invisible-hover-regression-results.txt。本次为相关模块回归，不替代游戏内视觉验收。安装后由玩家重启游戏验收。
