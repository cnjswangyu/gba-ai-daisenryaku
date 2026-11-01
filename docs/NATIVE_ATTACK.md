# 可见窗口与无按键原生攻击（2026-10-18）

已在用户可见的BizHawk窗口里验证：通过Lua提交原生函数调用，直接指定攻击者与目标，
由游戏进行武器选择、伤害、反击、扣弹、燃料处理和行动完成；攻击过程中没有注入A、方向或确认键。

## 为什么之前看不到窗口

诊断发现，普通沙盒命令启动的模拟器位于`WinSta0/CodexSandboxDesktop-...`。
把窗口从Hidden改成Normal仍然留在那个隔离桌面，不能出现在用户正在看的桌面。

本次通过正常桌面启动权限启动GUI，核验游戏窗口位于`WinSta0/Default`，Visible=true、Minimized=false。
用户随后确认看到了窗口。证据：`logs/window_visibility.json`、`logs/visible_window_verified.json`。
另外`Process.MainWindowHandle`曾指向输入指示器，不能据此认定已展示BizHawk主窗口；现在按进程ID及主窗口标题识别。

`Start-Native-Attack.cmd`可由用户在自己的桌面双击启动。它复用已有的本实验实例，保留用户调整过的窗口大小。
从Codex工具启动时应使用获准的正常桌面启动路径，不能只改`WindowStyle`，也不需要更改全局沙盒设置。

## 两次真实攻击

| 实验 | 目标HP | 我方HP | 武器弹药 | 行动状态 |
|---|---|---|---|---|
| U0(M1A2)攻击E0(T-72B) | 12→8 | 16→13 | 我方武器0：4→3；敌方武器1：1→0 | true |
| U1(M1A2)攻击E1(T-72B)，完整演出 | 12→8 | 16→12 | 我方武器0：4→3；敌方武器1：1→0 | true |

位置通过单独的POSITION命令放到合法邻格。ATTACK本身不移动或瞬移单位，也不写入HP或胜负字段。
第二次实验录像：`shots/native_attack/full_combat.gif`，帧截图中可直接看到两方坦克开火。
实验状态：`states/native_attack_verified.State`与`states/native_attack_visible_verified.State`。
保存前会卸载代码补丁，单独加载实验状态不会跳往空的代码区；之前的通关存档没有覆盖。

## 调用机制

1. 在战场每帧正常调用的地图输入函数`0x08018AF4`入口，临时放置8字节Thumb绝对跳转。
2. `0x0203FC00`处96字节调用桥，读取`0x0203FE00`的函数与6个参数。
3. 使用游戏当前调用栈执行原生函数；前4参数走R0–R3，后2参数走栈。
4. 保存返回值，验证调用前后SP相同，然后正常返回原游戏主循环。
5. 无命令时重放原入口指令，继续原有地图输入逻辑。卸载时恢复原入口与借用内存。

Lua不会直接改PC/LR，也没有靠CPU寄存器强跳来抵抗VBlank中断。
4组原生距离函数测试返回0、1、2、6；实战与刷新调用的SP均为`0x030075C4`，前后一致。
玩家阵营`ctx+0x990`保持0。

| 地址 | 功能 |
|---|---|
| `0x08023940` | 按目标类别、距离和弹药选择可用武器 |
| `0x08023188` | 完整原生战斗，参数：攻击方、攻击槽、攻击武器、防守方、防守槽、防守武器 |
| `0x0801F078` | 原生行动燃料处理，攻击者存活时调用 |
| `0x0801F130` | 原生设置已行动标志，攻击者存活时调用 |
| `0x080169D4` | 将镜头移到单位所在位置 |
| `0x08016BE0` | 重绘地图、单位图形、HP、行动状态与光标 |

代码桥自身先置busy，完成时再置done，支持安全拒绝已行动单位与重复安装/卸载。
游戏读取的完整演出开关实际是`0x030010D5`；旧记录中的`0x0300756F`只是设置界面的临时变量。
已实测直接写0/1切换，命令`ANIMATION OFF|ON|TOGGLE|STATUS`；同存档对照与独立Lua见[攻击动画开关](ATTACK_ANIMATION.md)。

## 使用

先双击项目根目录`Start-Native-Attack.cmd`。新实例从初始测试战场载入，打开完整演出，恢复真实键盘输入。
已有实验实例会复用，接着当前局面。若需要重新开始：

```powershell
python tools/native_attack.py LOAD first_clear_start
python tools/native_attack.py ANIMATION ON
```

从初始状态演示一次：

```powershell
python tools/native_attack.py POSITION 0 18 29
python tools/native_attack.py ATTACK 0 0
```

`POSITION`是已有的内存辅助移动；`ATTACK`要求单位已在武器射程内。
命令格式为`ATTACK <我方槽号> <敌方槽号>`。双方槽号和状态可用`SNAP --full`查看。

```powershell
python tools/native_attack.py SNAP --full
python tools/native_attack.py UNINSTALL
```

本实验由`tools/native_attack.py`生成`lua/native_attack.lua`与`lua/native_attack_stub.bin`。
Python只负责文件握手；调用桥与原生战斗调度都在模拟器内执行。
运行日志在`logs/native_attack.txt`，完整命令及状态在`shots/native_attack/journal.jsonl`。

## 验证范围与剩余工作

- 已实际验证：距离函数、两次M1A2对T-72B攻击、完整战斗动画、反击与扣弹、已行动拒绝、调用栈平衡、镜头重绘、补丁反复安装卸载。
- 当前接口固定用于此ROM的单机蓝方0对红方1；它不是其他GBA游戏的通用攻击API。
- 还未验证：间接炮击、空海军、多目标武器、最后一击与投降等需要确认框的完整无按键处理。
- 第一关通关仍是此前的内存辅助与游戏输入流程；本次证明攻击可以绕过按键菜单调用，尚未重新用此桥全程打完第一关。
- 静态证据：`logs/direct_attack_findings.md`、`direct_attack_core.c`、`direct_attack_render*.c`及`direct_attack_visibility.c`。这些来自本地Ghidra分析，不是REA MCP输出。
