# Phase 1 验收记录

日期：2026-09-11

**状态更新：用户已明确确认“phase1 实机验收通过”，据此进入 Phase 2。
以下保留首次交付时的测试及环境阻塞记录，不代表当前状态。**

## 已执行

- 从本机 Balatro.exe 提取版本、RNG、原版菜单及运行状态代码。
- 使用游戏自带 lua51.dll（LuaJIT 2.0.5）运行 tests/run.py。
- 加载原版完整 UI_definitions.lua，使用真实 UI 构建函数测试注入。
- 所有当前模组 Lua 文件通过 LuaJIT 加载/执行路径；语言键覆盖一致。
- 覆盖无对局、加载中、随机局、当前/待选/已完成盲注。
- 覆盖快照与原始对象分离、RNG 序列不变。
- 覆盖暂停菜单稀疏数组、原有按钮保留、主菜单不注入、重复打开不重复添加。
- 覆盖 42 次菜单打开/刷新/切页/禁用操作的游戏状态与 RNG 表身份保持。
- 将 math.random / math.randomseed / pseudoseed / pseudorandom / get_current_pool
  改成抛错替身后，Oracle UI 构建未调用这些接口。
- 验证未知版本明确提示且预测门禁保持关闭。

无窗口测试的 DynaText / UIBox / Sprite 是替身，不能证明字体排版、对象销毁、
手柄焦点、动画或既有模组组合兼容性。

## 实机尝试

已构建独立游戏副本，保留原版运行资源，只在测试副本的 conf.lua 设置
identity 为 Balatro/OracleValidation，防止测试写入原有档案。
测试副本不打包分发。

从受限命令环境启动时，Lovely 0.9.0 初始化成功；
LÖVE 在加载模组前退出，日志：

    Error: [love "boot.lua"]:48: Failed to initialize filesystem: no error

这是实机验收阻塞，不能将它报告为 Oracle 已正常加载，也没有证据将原因
归结为 Oracle Lua 错误。用系统自带 DLL 单独调用 PHYSFS_init 也返回失败。
参考 [LÖVE 文件系统初始化实现](https://github.com/love2d/love/blob/11.5/src/modules/filesystem/physfs/Filesystem.cpp)。

随后通过 Computer Use 请求正常桌面启动，结果：

    Computer Use app approval timed out

没有拿到游戏窗口、截图或实际 MATCH 记录。

## 安装与存档完整性

已新增 %APPDATA%/Balatro/Mods/Oracle。没有替换游戏目录的 EXE、DLL、
Steamodded 或其他模组。未发现旧 Oracle，因此不存在覆盖旧 Oracle 的情况。
游戏关闭时可删除 Mods/Oracle 卸载。

既有 profile 1 / profile 2 所有文件 SHA256 前后相同。
settings.jkr 前后 SHA256 均为：

    FF320DB11B59B4A7BC2E9AA495E1EB9D743A827C9BDDE4AF202A75DE18213F8E

## 首次交付的实机验收清单（后续已由用户确认通过）

1. 正常启动游戏，确认 Steamodded 列表出现 Oracle 0.1.0 且没有加载错误。
2. 开始普通随机局，暂停 → 预知，核对 Seed / Ante / Stake / Deck。
3. 待选 Small / Big / Boss、打牌中、结算、商店分别核对 Blind 标签与对象。
4. 总览、设置、刷新、返回、Esc、重复打开各测试；核对开关持久化。
5. 中英文、窗口/全屏、低分辨率、鼠标和手柄测试；确认无溢出和残留 UI 对象。
6. 与已安装 DVPreview / JokerDisplay / MoreSpeed / Always_Show_Seed 共存测试。
7. 记录实际截图和日志，修复发现的问题，全部通过后才开发 Phase 2。

本版没有未来预测，所以不产生虚构的 Shop/Boss/Voucher MATCH 记录。
