# （存档）项目最初的 README（2026-10-18）

> 这是公开发布前的主 README，保留作历史记录。当前入口见根目录 [README.md](../README.md)。
> 其中 `shots/`、`logs/`、`states/` 路径与本地模型链路属早期探索，主线后来转向原生函数调用。

---

# GBA AI —— 用本地大模型玩 Game Boy Advance

> **打完当前这一关**：打开模拟器并选到要玩的第一/二关，双击 `Play-Current.cmd`，自动找到可见窗口，从选关、出击前或已开战现场接着打完本关，保留当前累计成绩。[支持界面与使用说明](PLAY_CURRENT.md)。

> **重复刷第一关升军衔**：`Farm-Stage1.cmd` 在每局结算后沿用同一档案再进第一关，累计评判 P，军衔晋升即停。[使用与恢复说明](FARM_STAGE1.md)。

> **第二关一键程序已通关实测**：双击 `Play-Stage2.cmd`，保留老兵经验、补齐 20 单位、自动部署并战斗。完整复跑第 6 回合「大勝利」，剩 19 单位、1836 P，保留胜利窗口。`--fast --state stage2_t5` 可接续回合存档。[使用说明](PLAY_STAGE2.md)。

> **地图与经验查询**：出击编成界面双击 `View-Map.cmd`，打开 R 预览并生成全图；`python tools/native_attack.py XP ROSTER` 查看老兵经验、等级及地址。[第二关配置建议](STAGE2_MAP_PLAN.md) · [经验字段](UNIT_EXPERIENCE.md)。

> **第一关一键运行入口**：双击 `Play-Stage1.cmd`，自动部署、战斗并处理投降确认，保留胜利窗口。完整复跑已在第 7 回合取得「大勝利」，剩 16 单位、1706 P。默认 200% 速度；`--speed 100` 可原速观看。修复记录和产物见 [PLAY_STAGE1.md](PLAY_STAGE1.md)。

> **攻击动画开关已逆向实测**：`0x030010D5` 写 0 关闭完整演出、写 1 开启。同存档攻击分别用 201/501 帧，伤害与扣弹一致。[独立 Lua 与使用说明](ATTACK_ANIMATION.md)。另有一份供后续 agent 直接接手的[完整过程记录](AGENT_HANDOFF_ANIMATION_REVERSE.md)。

> **可见窗口与直接攻击已验证**：双击 `Start-Native-Attack.cmd`，使用 `python tools/native_attack.py ATTACK <我方槽> <敌方槽>` 直接调用原生战斗，保留动画、反击、扣弹和行动标志。单位需先进入射程。详情见 [NATIVE_ATTACK.md](NATIVE_ATTACK.md)。

> **最新进展（2026-10-18）**：《大战略》第一关已通过内存辅助移动与原生战斗，在第3回合取得「大勝利」。胜利存档：`states/first_clear_victory.State`；回放：`shots/first_clear/final_victory.gif`。规则纠正与完整记录见 [FIRST_CLEAR.md](FIRST_CLEAR.md)。本次由代理选择战术，尚未证明本地模型自主通关。

当前《大战略》主线是 `tools/ai_loop.py`（语义决策）与 `lua/usa_ai_state.lua`（游戏状态及执行）。下文的 `brain_file.py/state_agent.lua` 是早期通用实验链路。

> **项目位置**：`D:\prog\gba-ai`（原在 `C:\Users\Administrator\WorkBuddy\2026-10-17-18-56-53\gba-ai`，2026-10-17 迁至 D 盘）
> 模拟器：`D:\prog\gba-ai\tools\EmuHawk.exe`

两条输入路线，同一套执行层：

| 模式 | 喂给模型的东西 | 上下文大小 | 单步耗时 | 语义 |
|---|---|---|---|---|
| 视觉 `gba_agent.lua` | 240×160 截图（放大 4×） | ~800 视觉 token | 3–10 s | 强（模型自己看） |
| **内存 `state_agent.lua`** | **GRID 网格 + OAM 坐标 + RAM 活跃块，纯文本** | **~1 KB** | **3–5 s** | 弱（只有硬件层语义） |

## 目录

```
gba-ai/
├─ brain_file.py          ← 主大脑：轮询 state.txt，调本地模型，写 action.txt
├─ brain.py               ← HTTP 版（BizHawk 的 comm.httpPost 在本版本会挂，保留备用）
├─ test_vision.py         ← 单图测试：验证模型能不能读清 GBA 小字
├─ download.py            ← 多线程断点下载（GitHub 单连接被限速时用）
├─ lua/
│  ├─ state_agent.lua     ← 【内存模式】主循环：读内存 → 等模型 → 按键
│  ├─ gba_agent.lua       ← 【视觉模式】主循环：截图 → 等模型 → 按键
│  ├─ probe_mem.lua       ← 内存探测：列出内存域、IO 寄存器、OAM、分区占用
│  ├─ mem_scan.lua        ← 内存扫描：4KB 分块指纹 + 帧间变化块定位
│  └─ tile_ascii.lua      ← VRAM 解析：把 BG 图块还原成 #/. 字符画
├─ tools/                 ← BizHawk 2.11.1（解压即用，已装 .NET 8 桌面运行时）
├─ roms/ucity-advance.gba ← 开源测试 ROM（UCity Advance，城市建设类）
├─ shots/                 ← state.txt / action.txt 握手文件 + 截图
└─ logs/                  ← brain_file.log、steps-*.jsonl 决策流水
```

## 跑起来

```bash
# 1) 大脑（保持前台/后台常驻）
py -u brain_file.py --profile strategy

# 2) 模拟器 + Lua
tools\EmuHawk.exe roms\ucity-advance.gba --lua="lua\state_agent.lua"
```

换游戏只改 ROM 路径。`.gba` 由 BizHawk 的 mGBA core 加载。

## 内存模式下模型看到什么

`state.txt` 每步由 Lua 生成，**不含任何像素**：

```
step=7 frame=1865
DISPCNT=0x0540
BG0: 开启 4bpp map=0x0600F000 char=0x06008000
BG2: 开启 8bpp map=0x0600C000 char=0x06000000
GRID(BG2 30x20, 0=空, 其他=图块编号, 网格非空格=595):
  13 13 13 13 13 13 15 13 13 13 13  3  4 19 20 20 20 20 20 20 20 20 21  4  4  5 13 13 13 13
  ...
OAM: 0 个精灵（无单位/无光标）
MEM: 活跃 RAM 块
  IWRAM 0x03000000 非空 48%
  IWRAM 0x03003000 非空 51%
```

- **GRID** = 背景图块编号网格。相同编号 = 同一图案；模型据此判断界面布局、菜单框、地图边界。
- **OAM** = 精灵表（屏幕像素坐标）。**战棋游戏里一个精灵基本就是一个单位或光标**，这是最值钱的信息。
- **MEM** = 还在用的 RAM 块，用来判断"游戏在跑还是在等"。

决策结果写回 `action.txt`，Lua 只认 `step` 匹配的回复，避免错位。

## 已知局限

1. **UCity 的 OAM 是空的** —— 它把所有东西画在 BG 上，所以内存模式在它身上只能看到"网格结构"。换成《大战略》这类用 sprite 画单位的游戏，OAM 会直接给出单位坐标。
2. **没有业务语义**。GRID 里的 `13 13 13` 模型能看出"这是一片同质地形"，但看不出"这是森林，防御 +2"。金钱、回合数、单位 HP 都在 RAM 变量里，**必须逆向才能定位**。
3. BizHawk 的 `comm.httpPost` 在 2.11.1 会卡住（Lua 侧不返回），所以主通道用文件握手。

## 下一步（要精确读状态就得逆向）

目标：把"0x03004A20 处一个 12 字节结构"变成"第 3 回合，我方坦克在 (7,4)，HP 8/10"。

1. `lua/mem_scan.lua` 找活跃区（已能输出变化块的指纹）
2. `rea` + Ghidra 打开 ROM，搜 RAM 地址的读写引用 → 反推结构体字段
3. 把字段地址写进 `state_agent.lua` 的 `read_game_state()`，替换掉通用的 GRID/OAM
4. 之后模型看到的就是 `turn=3 money=1250 unit[0]={x=7,y=4,type=tank,hp=8}`
