# 多阵营 + 城市补给 —— v2（Play-Current2）逆向与实现

> 对应入口：`Play-Current2.cmd` → `tools/play_current2.py` → 构建 `lua/current_battle2.lua`
> 旧版（单阵营）：`Play-Current.cmd` → `tools/play_current.py` → `lua/current_battle.lua`（原样保留，未改动）

---

## 1. 用户报告的问题

> "当前版本就考虑一个敌人，遇到多个敌人的时候就出问题了"（红方、黑方等多个阵营）
> "还要考虑到占领的城市可以恢复 hp 和加油，要好好利用"

实测确认：`lua/current_battle.lua`（v1）里敌方只有 **一个阵营表**（`U + PB`，PB=0x600），
`军事演习3`（BLUE / RED / GREEN）下 RED(27) + GREEN(28) 两个敌对阵营，v1 只统计/只打 RED：

```
states/current_20261018_221519_ready.State   我方 side0=40, 阵营1=27, 阵营2=28
格表归属分布 {0:2114, 1:40, 2:27, 3:28}
```

---

## 2. 阵营结构（逆向结论）

| 结构 | 表达式 | 依据 |
|---|---|---|
| 单位表 | `ctx + 0x2760 + side*0x600`，stride `0x18` | HANDOFF §0.9.4b |
| 势力上限 | **4 个（0..3）** | `FUN_08018ca0`：`uVar5 < 4` 遍历 |
| 阵营记录 | `ctx + 0x24 + side*0xC`：`+0` 资金 u32，`+4` 状态 | `FUN_080023c4` = `(byte[+4]-1) < 3` → 1..3 = 参战 |
| 当前/玩家阵营 | `ctx+0x22`（当前操作方） / `ctx+0x990`（玩家） | HANDOFF |
| 格表归属 | `ctx+0x3F60 + x*4 + y*0xC0` 的 `+0` = 阵营+1 | 实测 |
| 场景数据 | `ctx+0x14` → RAM 副本：`+0x00` 标题(16B) + `0x10+i*0x18` 阵营块 `{名称(16B), 类型(1本国/2他国), …, 资金 u32}`；`+0x79` = 回合上限（本剧本 30） | 实存解析 + `FUN_08017bcc` |
| **战斗结算** | `FUN_08023188(我方阵营, 槽, 武器, **敌方阵营**, 敌槽, 反击武器)` | 反编译；v1 把第 4 个参数写死成 `1` |

**旧桥的根因**：`native_call(0x08023188,{0,idx,wa,1,eidx,wb})` 第 4 参数硬编码 `1`，
所以第二个及以后的敌对阵营从来没被打过，也没被统计。

## 3. 城市补给（实测矩阵）

回合开始时，**站在「地形 ∈ {0x10 首都, 0x11 市街, 0x14 村落} 且归属 = 本阵营」**的单位
HP / 燃料 / 弹药 **全部补满**。

实验：把 31 个单位分别放到伪造的 25 种建筑 + 敌归属对照 + 野地对照上，跑一个回合边界
（`tools/make_resup_matrix.py` + `tools/resup_probe.py`，日志 `logs/resup_after.txt`）：

| 地形 | 我方归属 | 敌方归属 | 结论 |
|---|---|---|---|
| 0x10 首都 | ★ 全补满 | — | 补给点 |
| 0x11 市街 | ★ 全补满 | ✗ | 补给点 |
| 0x12 | ✗ | ✗ | 不是补给点 |
| 0x13 | ✗ | ✗ | 不是 |
| 0x14 村落 | ★ 全补满 | — | 补给点 |
| 0x15..0x28 | ✗ | ✗ | 都不是 |
| 0x01 野地 | ✗ | — | 不是 |

→ **只有 首都/市街/村落 三种**（且归属必须是自己）。这也解释了"占领的城市能回血加油"。

## 4. v2 的改动

### 4.1 桥核心（`tools/native_attack.py --build --current2`）

* `lua/current_bacth2.lua` 前缀：`unit_side/unit/all_units` 支持 0..3 号阵营；
  `"EN"` = **所有敌对活跃阵营的并集**，每个单位带 `side` 与 `key = side*64+slot`（复合唯一键）。
* 原生调用全部按目标阵营参数化：战斗结算、反击武器读敌方弹药、占领 `FUN_08020B20(side,slot)`。
* 敌首都改成列表 `enemy_capitals()`（多阵营一个都不漏）。
* 状态导出的敌方行追加 `sideN`（行尾追加，旧解析器不受影响）。
* 攻击/回合日志带上 `sideN`，能直接看出打了哪个阵营。

### 4.2 战术（`lua/current_tactics2.lua`）

* 开局打印 `FACTIONS/FACTION/SIDES`：每个阵营的名称/类型/资金/是否敌对。
* 威胁评估、拦截任务、步兵占城任务都按**全部敌对阵营**计算；拦截名额随阵营数放大
  （`limit = max(3, #my * (0.25 + 0.1 * #foes))`）。
* **补给感知**：
  * `cs_supply_cell(x,y)`：首都/市街/村落 + 归属我方；
  * `cs_needs_supply(u)`：HP ≤ 70% / 燃料 ≤ 12 / 没弹药 → 需要补给；
  * 缺编单位本回合会**主动走到自家补给点上收尾**（下回合补满），并"原地驻守补给自己"；
  * 满编单位不会被钉在城里（`cs_hold` 只在需要补给/受威胁/首都守卫时才留守）；
  * 占城任务给补给地形加权（`-22`），优先占能当补给站的城；
  * 推进打分对"结束在自家补给点"给 +260（缺编）/ +45（满编）。
* 自家补给城市全部纳入防守（首都优先），被威胁的城市加预备队。
* 投降/最后一击、`ctx+0xC55` 演出开关等沿用 v1。

### 4.3 灭国坑（重要，已实测定性）

**杀掉某一敌对阵营的最后一个单位 → 游戏进入灭国演出，原生战斗调用再也不返回**：
预算放到 6000 帧仍然 `did not return`，PC 停在 `0x080006C2`（ROM 向量区）或 EWRAM 垃圾地址，
再装 hook 也没用。因此 v2 的策略是：

* 只要还有别的敌对阵营活着，**不打"某方的最后一个单位"**（`cs_eliminates_faction`），
  改为先削其他阵营 + 去占它的首都（场景胜利条件本来就是"占領敵方的首都"）；
* 单一阵营时最后一击不受限（= v1 的正常胜利路径）；
* 万一真的卡住，`cs_recover_stuck()` 会清 mailbox、写回原始 8 字节、清 EWRAM 桥区、推 A 过演出、
  再装回 hook；装不回就**干净地停手**并提示"重跑 Play-Current2 继续"，不会写坏游戏。

## 5. 验证

| 测试 | 结果 |
|---|---|
| `tools/check_current_tactics2.py`（lua54 离线编译 + 夹具） | PASS：语法 / 多阵营枚举 / 补给地形判定 / 缺编判定 / 缺编单位回城 / 原生调用全部带阵营 |
| `tools/faction_smoke.py`（真实内存） | `MY=40 EN=55 enemy_sides=[1,2]` —— v1 只会看到 27 |
| `tools/v2_battle_test.py`（端到端） | 同时攻击 side1 与 side2（`{1:3, 2:3}`），全程不崩，我方补给城市增长到 15 |
| 城市补给矩阵 | 见 §3 |

已知限制：极小残局（每方只剩 1 个单位且都在城里回血）时 30 回合内收不掉尾；正常规模地图
（每方十几~几十个单位）不触发此问题。空/海军、间接炮击、多目标武器未覆盖（同 v1）。

## 6. 怎么跑

```
Play-Current2.cmd                  # 双击；或 python tools/play_current2.py
python tools/play_current2.py --check          # 只接管并打印阵营信息，不打
python tools/play_current2.py --speed 800      # 战斗速度
```

前置：先自己开着游戏进到战场/出击编成/关卡选择，再运行（接管当前窗口，不载入固定存档）。

## 7. 相关文件

```
Play-Current2.cmd                  # 入口
tools/play_current2.py             # 控制器（互斥锁、握手、日志跟随）
tools/native_attack.py             # 桥核心；新增 --current2 变体（v1 路径零改动）
tools/current_tactics2.py          # v2 装配（前缀多阵营 + 原生调用参数化 + 战术插入）
lua/current_tactics2.lua           # v2 战术模块
lua/current_battle_flow2.lua       # v2 开局流程（打印阵营、部署、开打）
lua/current_battle2.lua            # 生成产物
tools/check_current_tactics2.py    # 离线校验
tools/faction_smoke.py             # 多阵营识别冒烟测试
tools/v2_battle_test.py            # 端到端战斗测试
tools/make_resup_matrix.py / resup_probe.py   # 城市补给矩阵实验
tools/make_v2_battle_fixture.py    # 小规模多阵营战局夹具
```
