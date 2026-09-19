# Phase 7 — Oracle 0.7.0

Phase 6 / 0.6.0 已由玩家验收通过。本阶段保留原版 UI 和所有条件预测边界，集中验证异常路径与扩大随机状态样本。

## 修复

1. `rng.new` 先复制数据，再分配私有 Lua 状态。无效类型不再提前分配需要依赖 GC 回收的后端。
2. `ante_prediction.run` 将 RNG 状态导出纳入受保护调用，模拟回调或导出失败都显式关闭私有状态。
3. `create_card_for_shop` / `get_pack` 验证包装器保留完整返回值元组，包括 nil；只归一化第一个值用于核对，不丢弃扩展返回值。

没有修改 pseudoseed 算法、抽选顺序、候选池、贴纸或版本生成规则。错误路径仍然拒绝相关预测，不推进真实 RNG 来尝试修复。

## 可重放回归

```powershell
python outputs/Oracle/tests/run.py --stress --game-dir D:/steam/steamapps/common/Balatro `
  --patched-dir "$env:APPDATA/Balatro/Mods/lovely/dump" `
  --smods-dir work/runtime-mods/Steamodded --report oracle-regression.json
```

- `--stress` 包含 Phase 1–7 和标签/标签链测试，扩展为 1000 个商店 seed、300 个五类补充包 seed、300 个六类 Joker Tag seed、100 个标签链 seed，以及 1000 个交错 RNG seed。固定特殊场景另外执行。
- Phase 2 保留 200 seed × 8 Ante 和 60 seed × 20 个未来 Ante 的原版对照。完整运行不使用 `--fast`。
- 样本 seed 是固定前缀加索引，如 SHOP123、PACK4_123、TAG123、CHAIN123_1 和 RNG7_123；不是随机挑选的不可重放样本。
- `--seed-start 1001` 更换五个扩展扫描的起始索引；固定边界用例与 Phase 2 保持不变。失败信息附带测试名称、seed、Ante，以及适用时的包 key、标签、栏位和 Double 数量。
- JSON 报告包含实际提取的原版函数、Oracle Lua/Python 测试代码和游戏 lua51.dll 的 SHA-256、运行耗时、是否跳过 Phase 2 及通过/失败状态。失败报告保留 traceback 和 Expected/Actual。
- 原版对照直接在游戏自带 LuaJIT 中执行；渲染、声音、持久化和部分事件环境使用测试夹具。源码提取在临时目录完成，发行包不含游戏源码或玩家存档。

## 新增异常/边界检查

- 无效快照在分配前拒绝。
- 商店回调参数、nil 返回值和一次执行约束。
- 后端拒绝无效 seed，重复关闭安全，真实全局 RNG 序列不变。
- 连续模拟异常及状态导出异常均关闭后端，输入和真实游戏快照不变。
- 验证日志磁盘写入失败不改变游戏返回值；检测到 mismatch 后继续关闭预测。
- 正常商店 → 重掷过渡 → 零栏位 → 四栏位时不返回旧缓存。
- 多 seed、重复 key、resample key、空字符串 key、零初始状态和整数区间抽样与原版逐次一致。

## 验证边界

此处的大量样本是实际生成函数的自动化对照，不等同于数千局从头到尾的实机通关。未覆盖的第三方回调仍保持不可预测；多步玩家选择仍是条件分支。英文实际布局、所有分辨率和长时间实机性能不能由这些测试证明。

## 最终结果（2026-09-14）

完整 `--stress` 运行通过，未跳过 Phase 2，耗时 198.113 秒。合计 77 项测试：

| 模块 | 通过测试 | 生成结果对照 |
| --- | ---: | ---: |
| Phase 1 加载 / UI | 11 | — |
| Phase 6 设置 / 分页 | 6 | — |
| Phase 2 Blind / Tag / Voucher | 13 | 17,846 |
| Phase 3 商店 / Boss 重掷 | 7 | 13,480 |
| Phase 4 补充包 | 8 | 7,767 张候选牌；8 次 Soul、13 次 Black Hole |
| Phase 5 牌序 / 同步 | 5 | — |
| Skip Tag | 11 | 5,864 张商店牌 |
| Double / Voucher 标签链 | 9 | 1,579 个原版链场景 |
| Phase 7 异常路径 / RNG | 7 | 40,000 次 RNG 抽样 |

原始输出见 `phase7-test-results.txt`；源码指纹和运行参数见 `phase7-regression-report.txt`（内容为 JSON）。不同计数的单位不同，不将其相加宣称为实机局数。

已备份本机 0.6.0 并安装 0.7.0，安装前后用户 config.lua 哈希一致，运行 Lua 与交付目录逐文件哈希一致。备份位于工作区 `work/backups/Oracle-before-phase7-20260914-000537`。

本机启动日志在 00:05:56 确认 Oracle 0.7.0，随后观察到 CZZXRBWB 存档的原版风格总览正常显示。本次助手没有执行购买、重掷、出牌或弃牌；检测到用户操作后只重新读取界面，没有继续抢占输入。

启动检查发现 Steamodded `src/preflight/loader.lua` 使用 `filename:lower():match('%.json')` 扫描文件。最初的测试报告名称触发无效清单提示；已将安装目录与发行目录中的报告重命名为不含 `.json` 的 `.txt`，并检查仅 Oracle.json 会匹配。此修复只涉及文档文件名，无须改写运行代码。当前会话已记录的那条提示不会被抹去；下次启动使用修正后的文件布局。其他模组清单警告及旧有商店区域加载提示仍单独保留，不视为 Oracle Lua 异常。

建议实机验收继续覆盖常用购买 / 出售 / 两种库存过剩、标签跳过、开包与连续重掷；若出现 MISMATCH，保留对应诊断日志。Phase 7 的自动回归通过不替代这些实机操作验收。
