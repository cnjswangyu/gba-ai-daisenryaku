# 第一关通关记录（2026-10-18）

第一关「軍事演習１」已在第 **3 回合**取得原生 **大勝利**。
由本聊天中的代理选择目标，Python 文件命令驱动 BizHawk Lua；本次没有启动本地模型自主决策。

## 结果与证据

- 起点：`states/battle_usa_ready.State`，美国，全车辆编成，实际部署19单位。
- 终点：`states/first_clear_victory.State`，我方18单位、敌方0单位。
- 游戏内存：`ctx=0x03000480`，`state=8`、`turn=3`、`player=0`、`ctx+0x2C=2`。
- 画面：`shots/first_clear/victory.png`，美国国旗与「大勝利」。
- 最后交战、投降与胜利动画：`shots/first_clear/final_victory.gif`。
- 最后一击前：`states/first_clear_before_last.State`。
- 操作与状态记录：`shots/first_clear/journal.jsonl`；运行日志分段保存在 `logs/first_clear*.txt`。

移动和瞄准使用内存辅助：同步占用格、单位坐标、光标；移动不受正常移动力和路径限制。
输入由原项目的读键邮箱补丁注入。攻击、反击、单位删除、投降、奖励和胜负都由原游戏执行。
没有把敌军HP改成零或直接设置胜利标志。本结果是内存辅助通关，不是遵守完整移动规则的通关。

## 实际打法

1. 第1回合用M1A2清除敌方侦察、炮兵与补给车辆，再削弱近处坦克。
2. 第2回合集火击毁威胁我方首都的坦克，推进至敌方首都，消灭一支步兵。
3. 第3回合两辆M1A2击毁首都守军（HP9→4→0），另一辆消灭最后步兵（HP24→0）。
4. 接受敌军投降，游戏进入结算并显示「大勝利」。

研究期间有错误按键导致的解散，均回滚到之前的存档重试；这些分支不计入最终战局。
最终有效分支的损失是第1次敌方回合被击毁的一辆补给车。

## 已纠正的关键规则与字段

历史README和HANDOFF中的部分推断已被下列实测/原生代码证据推翻。

| 问题 | 正确结论 | 依据 |
|---|---|---|
| `ctx+0x990` 当作选中单位号写入 | 实为玩家所属阵营；写单位号会污染资源和胜负逻辑 | `logs/main19.c`、`logs/menu_entry.c`、`logs/stridefuncs.c`；移除后连续作战验证 |
| 已行动标志读 `U+7` | 记录从ID开始，`U`指向坐标；应读`U+5`（记录+7）bit0 | `FUN_08018CA0`，攻击前后快照 |
| 每格坐标±2 | 真正相邻格由y奇偶决定；`(27,16)`与`(27,14)`距离2 | `logs/damage.c`，`FUN_08002DC4/08002E74` |
| 固定Down一次就是攻击 | 攻击缺失时第二项可能是解散；须检查当前有效菜单 | `logs/clear_menu_research.c`、`clear_attack_menu.c`、`clear_menu_sprite.c` |
| 模拟器光标能动就算下一回合 | 回合读`ctx+0x20`，阶段`+0x21`，行动方`+0x22` | 实际回合切换、`logs/battle7.c` |
| 全灭是否能胜 | 本关常规目标为占都；敌军全灭后还会请求投降，接受即可胜 | `FUN_08004780`、`logs/damage.c`、本次实际结算 |
| 天气名称 | 目前只证实码1=100%、码0/2=85%、码3=70%的地面攻击倍率，名称未证实 | `logs/weather_fn.c`、`dmg_deps.c` |

六角坐标使用odd-r偏移：`q=x-floor(y/2), r=y`。
距离为`max(abs(dq),abs(dr),abs(dq+dr))`。从ROM原生公式对照6561对坐标零差异；真实邻格也已在本次围攻中验证。

菜单读取先验证OAM槽`row+2`有效且tile为`0x228+row*8`，再用
`VRAM 0x06014500+row*0x100`前128字节匹配ROM菜单字形。
可选项源`0x0806A830`，禁用项源`0x0806B930`，每项0x100字节。
只接受可用action1（直射攻击）；action4是间接攻击，尚未在自动ATTACK中实现。

## 复现与查看

在BizHawk中加载`states/first_clear_victory.State`即可查看胜利画面。
也可从项目根目录运行：

```powershell
python tools/first_clear_control.py --build --load first_clear_victory
tools/EmuHawk.exe "roms/0219 - Daisenryaku.gba" --lua="D:/prog/gba-ai/lua/first_clear.lua"
```

`first_clear.lua`由控制工具从当前主线函数生成，用来隔离人工研究与模型文件通道。
它使用`shots/first_clear/command.txt`与`reply.txt`，不覆盖旧通道`shots/action.txt`。
可通过以下命令逐步研究，所有命令都会记录状态和截图：

```powershell
python tools/first_clear_control.py SNAP
python tools/first_clear_control.py KEY A 4 40
python tools/first_clear_control.py RECORD example
python tools/first_clear_control.py RECORD OFF
python tools/render_replay.py example
```

`RECORD`每6个被脚本推进的游戏帧保存一帧原始截图，GIF按100ms播放、最近邻放大3倍。
这是模拟器画面回放，不是桌面录屏或实时视频流。

## 剩余限制

- 自动ATTACK仍是移动辅助后贴身直射；炮兵间接射程和完整合法寻路需要另做。
- 地形通行、正常移动力与燃料消费没有构成完整公平规则约束。
- 本次成功证明控制层能通关，不代表本地小模型已经具备自主通关能力。
- 主线增加了原生胜负检测、接受投降、保存结算画面；完整模型自主循环尚未重新跑通一局。
