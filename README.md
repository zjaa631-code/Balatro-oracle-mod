# Oracle / 预知

Balatro 单机局内预测模组。读取当前牌局与随机流，在独立的模拟状态中预览商店、补充包、标签、抽牌和随机效果；预测不会推进真实牌局的 RNG。界面复用 Balatro 的卡牌与菜单组件。

当前版本：**0.16.3**。主要针对 **Balatro 1.0.1o-FULL、Steamodded 26.829.0、Lovely 0.9.0** 开发和验证；其他模组组合尚未作为准确性保证范围。

## 安装

1. 安装 Balatro PC 版、[Steamodded](https://github.com/Steamodded/smods) 和 [Lovely](https://github.com/ethangreen-dev/lovely-injector)。
2. 下载本仓库的 ZIP，解压后将文件夹命名为 `Oracle`，放入 Balatro 的 `Mods` 目录。Windows 通常为 `%APPDATA%\Balatro\Mods\Oracle`。
3. 确认 `Oracle.json` 与 `Oracle.lua` 直接位于 `Oracle` 文件夹内，然后重启游戏。

## 使用

| 操作 | 功能 |
| --- | --- |
| 局内左下角“预知”按钮或 `F8` | 打开 Oracle 页面 |
| `F9` | 撤销当前牌局最近一次已保存操作；账号解锁与生涯统计不回退 |
| `F10` | 导出诊断日志，便于排查预测停用 |
| 悬浮卡牌、标签、补充包或牌堆 | 查看下一次适用的快捷预测 |

主要页面涵盖商店与连续重掷、补充包候选及 The Soul 结果、Skip Tag 奖励、Boss、牌堆抽牌顺序、消耗牌与随机小丑事件。部分较远的条件分支标为 **Experimental**；若实际结果与预测不符，验证器会停止展示不可靠的后续预测，而不会静默给出确定答案。

Oracle 的预测是只读的。`F9` 撤销是单独的主动操作，只作用于当前牌局。使用前建议正常备份存档。

## 测试与诊断

本仓库包含原版函数对照测试和模拟器测试。0.16.3 在指定版本上通过 168 组自动回归；其中 Boss 候选池顺序修复见 [技术说明](docs/BOSS_POOL_ORDER.md)。完整变更记录见 [CHANGELOG.md](CHANGELOG.md)。

预测失效时，请按 `F10` 导出报告，并在反馈问题时附上报告、Balatro／Steamodded／Lovely 版本、牌局阶段及重现步骤。报告包含 seed 与 RNG 状态，公开提交前请自行确认是否愿意分享这些数据。

测试脚本入口为 `tests/run.py`，需要本机 Balatro 安装目录、Lovely 补丁转储和对应 Steamodded 源码。不要把游戏原版资源、个人存档或本机诊断日志提交到仓库。
