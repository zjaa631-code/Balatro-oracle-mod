# 0.13.0 悬浮快捷预览

本次仅实现用户指定的快捷预览；原定后续开发阶段仍暂停。

## 接入方式

prediction/quick.lua 在悬浮时捕获 detached snapshot，调用既有统一 engine 的 pack / consumable adapter。以完整输入快照签名缓存，每类保留一份；缓存结果返回副本。没有每帧预测，也没有先推进真实 RNG 再撤销。

牌堆由现有 deck reader 读取真实 deck.cards 尾部到头部，只在当前抽牌上下文显示；展示前 8 张，到下一次洗牌为止，不从 seed 重新创建初始牌组。商店、结算和盲注选择时提示下轮需要洗牌，不展示不成立的未来顺序。

ui/quick_preview.lua 在原版 G.UIDEF.card_h_popup 构建前追加文本。保持原说明、卡图和鼠标行为，不改 Card.generate_UIBox_ability_table，以保留 Oracle 原有隔离描述克隆功能。预览卡、收藏页和非局内对象不会误接入。原版 Card:hover 自有的声音和动画照常运行；Oracle 追加内容不调用随机函数。

牌堆通过 CardArea:hover 和牌堆中的 Card:hover 使用原版 popup；支持牌堆区域与顶牌两种实际命中对象，不翻牌或创建假卡牌。名称、本地化和色彩使用原有 Oracle/native formatter 与 G.C。

牌堆 popup 只保存在 children.h_popup，绝不写入 CardArea.config。原版 CardArea:save 会完整保存 config；将含 parent 的 UI 定义放入其中会使保存线程遇到 userdata。实机检查发现并修复了这个问题，新增测试直接执行当前原版 CardArea:save / STR_PACK，在可见 popup 内带 userdata 的情况下确认保存内容依旧可序列化、config 完全未改变。

## 展示范围与边界

- 商店补充包显示全部候选牌名，含版本、强化、蜡封和 Soul 的 Legendary 分支。复用既有 pack 能力门禁；Hallucination 等尚不支持的原版交互仍明确拒绝，不能跳过准确性检查。
- 持有、包内、商店中的消耗牌复用已有模拟。命运之轮失败只显示失败，成功显示具体目标和版本；女祭司与皇帝列出每张生成牌，依实际空位数量生成。
- 商店消耗牌为“按当前状态使用”的条件分支，明确不含购买效果。实际购买后重新悬浮会读取新快照。
- 手牌目标不满足、容量不足、过渡状态或版本门禁不通过时，显示已有本地化原因，不静默保留旧预测。
- 选牌、库存、牌组或 RNG 变化后重新悬浮会刷新。悬浮保持期间不每帧重建预测与 UI。

## 验证

tests/quick_preview.lua 使用实际 LuaJIT 与先前已提取的原版消耗牌调用链：80 seed × 4 张随机塔罗（审判、女祭司、皇帝、命运之轮）共 320 次实际使用，比较效果及完整 RNG 状态；悬浮前后比较真实快照与全局 math RNG。

补充包为 20 seed × 5 类、共 100 次既有预测 adapter 比对；该组验证快捷层没有丢候选或改 pack size，原版候选生成的独立比对继续由完整 Phase 4 测试负责，不把 adapter 自比宣称为额外原版验证。

另外测试缓存副本、RNG/手牌选择/库存变化、牌堆顶序/牌面变化/抽走后刷新、洗牌边界、关闭功能与失败门禁、保留原说明与重复 tooltip 去重、预览卡排除、原版描述函数不被替换、牌堆区域和顶牌入口、Soul 与版本名称、前 8 张限制。

```powershell
python tests/run.py --game-dir D:/steam/steamapps/common/Balatro --bosses --card-insight --quick-preview --patched-dir "$env:APPDATA/Balatro/Mods/lovely/dump" --smods-dir path/to/Steamodded --report quick-regression.json
```

自动化验证不代替实际悬浮提示的视觉验收；安装后重启游戏，在商店补充包、右下角牌堆和消耗牌上分别悬浮检查。

## 本次执行结果（2026-09-16）

修复后的完整单次回归：PASS，127 组全部通过。报告与输出分别见 quick-preview-regression-report.txt、quick-preview-regression-results.txt，包含实际源码与 LuaJIT 哈希。实际安装保留原 config.lua，并备份旧版本。

游戏已启动并确认加载 0.13.0。实机检查发现的保存线程崩溃已修复并安装；修复后原版 CardArea:save / STR_PACK 自动测试通过。按照玩家选择，修复后的重启、实际保存和悬浮视觉验收由玩家自行完成，未将其宣称为代理已完成的实机验收。
