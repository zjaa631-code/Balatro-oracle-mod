# 0.16.2：幻觉开包预测、事件调度与一键日志导出

## 原因与修复

0.16.0 的 pack capture 在持有 `j_hallucination` 时主动设置 `pack_unsupported`，因此即使其他预测正常，也会显示「当前状态或自定义规则暂不支持补充包预测」。该保护源于旧版未模拟幻觉开包副作用，并非随机种子或底注限制。

本机实际 Card.open / Card.calculate_joker / SMODS.blueprint_effect 调用链：

1. 分发 open_booster，按小丑顺序进行幻觉概率判定，成功时立即预占消耗牌栏位。
2. Card.explode 创建持续约 1.5 × explode_time 的阻塞事件。包内候选牌与 emplace 事件是 non-blockable，在约 1.3 × explode_time 时先执行。
3. 动画阻塞解除后，幻觉的 blockable 事件才生成塔罗牌，推进 `hal` 相关生成流，更新已使用牌与候选池。

Oracle 在 detached snapshot 中执行相同顺序。蓝图复制右侧小丑、头脑风暴复制最左小丑，遵守原版兼容标志、削弱与递归上限；所有概率判定先于排队生成，避免多个幻觉争用最后一个栏位时额外抽 RNG。五类包和标签赠送包使用同一模拟。开包实际验证使用候选牌全部 emplace 时的 rng_after；另存 settled_rng、opening_cards 和 settlement_trace，表示动画解除后生成塔罗牌的结果。Soul → Legendary 的条件分支使用动画结束后的 shadow 状态。

0.16.1 曾错误地将第 3 步放到第 2 步前。本次实际诊断显示五张卡牌一致，但验证时实际还没有 Tarothal5，而旧预测已经推进了该流，因而触发 MISMATCH。0.16.2 已修复该时间边界，并用用户导出的失败快照在本地重放核对了候选牌和完整 RNG。原始日志及完整牌局数据不随压缩包分发。

没有取消 mismatch 停用保护，没有修改或回滚真实 RNG。自定义 Soul、未知标签或未支持的自定义规则仍拒绝预测。当前只保证受验证的原版规则。

## 导出日志

- 按 F10，或「预知 → 导出日志」。即使预测被禁用也可使用；文字输入及撤销读档期间不会响应 F10。
- 使用原版暂停弹窗展示成功／失败，提供「打开日志文件夹」按钮。
- 每次生成单独 TXT 文件，同秒多次导出也不会覆盖旧报告。
- 内容：Oracle／Balatro／Steamodded／Lovely 兼容信息、LÖVE 版本、模组列表、设置、故障标志、近期快捷预览错误、当前 run／shop／pack／deck 只读快照、内存中的最近 mismatch，以及 Oracle 验证日志和最新 Lovely 日志尾部。
- 每份日志尾部最多 512 KiB，每个快照段最多 2 MiB；截断明确标记。某一快照不可读取会记录 SECTION ERROR，不影响其他段导出。无牌局也可导出版本和日志。
- 不读取 `.jkr`、全局 profile 存档、撤销历史；不上传、不重置故障、不推进预测。导出的 seed、RNG 和日志只在主动分享该 TXT 时交给接收者。
- 写入失败显示友好提示，不使游戏崩溃。Windows 默认保存于 `%APPDATA%\Balatro\oracle-reports`；其他环境使用 LÖVE 当前存档目录。

## 验证

新增多 seed 的五类包开包回归，调用本机原版 calculate_joker、blueprint_effect、创建牌与 Booster:create_card，逐项比较幻觉生成结果、包内卡牌与最终 RNG，覆盖多个幻觉、复制链／循环、削弱、Oops 概率和栏位／buffer。

0.16.2 另加载原版 Object、Event、EventManager、Card.open、Card.explode；仅对图形粒子等无关显示做替身，不替换调度。覆盖 4 种速度 × 3 种帧步长，断言卡牌进入包区域时幻觉生成仍排队、验证 MATCH 且预测未停用；队列最终清空后再比较生成塔罗牌及 settled_rng。之前仅手动调用原版回调的测试未覆盖动画阻塞，这是此次遗漏的原因。

导出回归覆盖禁用预测、版本不匹配、快照失败、日志缺失／过大、同秒重名、磁盘写入失败、F10、原版按钮与打开目录 URL。真实游戏的开包视觉和系统文件管理器仍需实机验收。
