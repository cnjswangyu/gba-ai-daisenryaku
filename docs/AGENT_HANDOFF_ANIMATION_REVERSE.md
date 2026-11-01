# Agent 交接：可见模拟器、原生攻击与动画开关逆向

本文记录 2026-10-18 在 `D:\prog\gba-ai` 完成的一次完整工作过程，供后续 agent 继续研究《大战略》GBA ROM。重点是：如何让用户看到 BizHawk、如何调用游戏自己的攻击函数，以及如何直接逆向并验证攻击动画开关。

## 当前结论

攻击动画的实际战场开关是单字节 `0x030010D5`，也就是游戏上下文 `0x03000480 + 0xC55`。

```lua
memory.write_u8(0x030010D5, 0) -- 关闭完整战斗演出，进入简化显示
memory.write_u8(0x030010D5, 1) -- 开启完整战斗演出
```

这是直接内存读写，不需要菜单按键，也不需要安装攻击调用桥。完整演出关闭后仍有简化战斗显示；不是让画面完全静止。

同一测试状态下，M1A2 对相邻 T-72B 攻击的结果如下：

| 设置 | 原生战斗调用帧数 | 我方 HP | 敌方 HP | 我方弹药 | 反击弹药 | 行动标志 |
|---|---:|---|---|---|---|---|
| OFF（0） | 201 | 16→13 | 12→8 | 4→3 | 1→0 | true |
| ON（1） | 501 | 16→13 | 12→8 | 4→3 | 1→0 | true |

结果证明开关影响演出路径和耗时，不改变这次结算结果。验证数据在 `logs/animation_ab.json`，录像在 `shots/native_attack/animation_off.gif` 和 `shots/native_attack/animation_on.gif`。

## 过程一：解决用户看不到窗口

普通沙盒启动的 BizHawk 位于 `WinSta0/CodexSandboxDesktop-*`，即使设置为 Normal，用户桌面也看不到。可见窗口必须使用正常桌面启动路径，并核验窗口所在桌面是 `WinSta0/Default`。

项目已有启动入口：

```text
Start-Native-Attack.cmd
```

它会调用 `tools/start_native_attack.ps1`，复用 `shots/native_attack/emulator_pid.txt` 中的实验实例。诊断窗口使用：

```powershell
powershell -NoProfile -File tools/window_diag.ps1 -Show
powershell -NoProfile -File tools/window_diag.ps1 -Place
```

不要只看 `Process.MainWindowHandle`：BizHawk 进程可能还有输入指示器窗口，真正的游戏主窗口标题以 `BizHawk` 结尾。用户已经确认当前正常桌面窗口可见。

## 过程二：原生攻击调用桥

为了让攻击过程在窗口中真实播放，采用了可卸载的 Thumb mailbox bridge。ROM 文件不修改，Lua 也不直接写 CPU 的 PC/LR。

关键位置：

| 地址 | 用途 |
|---|---|
| `0x08018AF4` | 正常地图输入函数入口，临时放置 8 字节 Thumb 跳转 |
| `0x0203FC00` | 96 字节 Thumb 调用桥 |
| `0x0203FE00` | mailbox：函数地址、6 个参数、返回值、SP 校验和状态 |
| `0x08023940` | 根据单位记录、目标类别、六角距离选择武器 |
| `0x08023188` | 原生战斗结算与演出 |
| `0x0801F078` | 攻击后的燃料处理 |
| `0x0801F130` | 设置已行动标志 |
| `0x080169D4` | 镜头定位到单位 |
| `0x08016BE0` | 地图/单位/HP/行动状态重绘 |

调用约定是前 4 个参数放 R0–R3，后 2 个参数放栈。桥每次调用都会检查：

1. 函数是否在审计白名单中；
2. mailbox 是否空闲；
3. 调用前后 SP 是否相同；
4. 玩家阵营 `ctx+0x990` 是否仍为 0；
5. 返回后再更新画面。

攻击命令不负责移动单位。合法射程位置由 `POSITION` 辅助设置，之后 `ATTACK <我方槽号> <敌方槽号>` 才调用游戏自己的武器选择、伤害、反击、扣弹和行动处理。

入口与桥的生成器是 `tools/native_attack.py`，生成文件是 `lua/native_attack.lua` 和 `lua/native_attack_stub.bin`。完整说明见 [NATIVE_ATTACK.md](NATIVE_ATTACK.md)。

## 过程三：动画开关的静态逆向

采用本地 Ghidra 对 ROM 做 Thumb 函数反编译，工程位于 `tools/ghproj3`。证据文件：

```text
logs/animation_switch.c
logs/animation_switch_menu.c
logs/animation_switch_save.c
```

核心发现：

| ROM 位置 | 结论 |
|---|---|
| `0x08022BE8` | 战斗流程读取 `ctx+0xC55`，严格判断是否等于 1 |
| `0x08025C98` | 值等于 1 时进入完整演出路径 |
| `0x08026000` | 其他值进入简化显示路径 |
| `0x0801AAAC` | 设置菜单第三行左右切换临时结构 `+3` |
| `0x0801A9D4` | `0A 70`，把菜单临时值提交到 `ctx+0xC55` |
| `0x08000272` | 初始化默认值为 1 |
| `0x0800170E` | 从保存缓冲 `+0x14` 恢复到开关 |
| `0x080017CE` | 把开关保存到保存缓冲 `+0x14` |

因此，旧记录中看到的 `0x0300756F` 只是设置菜单临时数据，不是稳定战场开关。历史文档里“必须走设置界面”和“直接写 0 无效”的说法已经推翻；后续 agent 应以本文件和 `docs/ATTACK_ANIMATION.md` 为准。

## 为什么这次看起来定位得很快：可复用的逆向经验

这不是从 8 MB ROM 里盲搜两个地址。之所以看起来像“一下子找到”，是因为前面的工作已经把搜索空间压缩了：第一关已进入真实战场，已经知道游戏上下文指针、单位记录、HP/弹药/行动标志和可复现的战斗存档；同时还解决了模拟器窗口不可见的问题，可以直接观察原生结果。后续只需要围绕一个可重复的状态变化做实验。

这次最有用的经验可以归纳为以下几条。

### 1. 先固定输入和输出，再找中间变量

不要一开始就在整份 ROM 中猜“攻击函数”或“动画变量”。先固定一个战斗状态，记录攻击前后的少量事实：攻击者和目标的 HP、武器弹药、行动标志、镜头位置、战斗持续帧数。然后每次只改变一个因素。

攻击入口就是这样收敛的：目标、攻击者和距离固定后，HP、弹药和行动标志必须由游戏自己的结算逻辑改变；只要能重复这个变化，就可以沿着调用链找真正的结算函数，而不是把 HP 直接改成目标值。最后确认到 `0x08023188` 后，又单独调用燃料、行动标志和重绘函数，证明它们分别承担不同职责。

动画开关的信号更明显：同一攻击、同一存档，只有一个字节不同，原生战斗调用从 201 帧变成 501 帧。这样的 A/B 差异比“画面看起来像变了”可靠得多。

### 2. 运行时扫描只负责找候选，静态交叉引用负责定案

RAM 扫描适合回答“哪些字节在这次操作中变了”，不适合单独回答“这个字节到底是什么”。候选地址必须继续追两条链：

- 谁读取它，读取后分支到哪两个函数；
- 谁写入它，写入来自菜单提交、初始化，还是保存/载入。

对 `0x030010D5` 的定案过程就是：先看到战斗演出开关有稳定的 0/1 行为，再从 `0x08022BE8` 的读取和严格的 `== 1` 分支追到 `0x08025C98`（完整演出）与 `0x08026000`（简化显示），最后从设置提交点 `0x0801A9D4` 反向确认写入来源，并检查保存/载入点。

这一步也解释了为什么旧地址 `0x0300756F` 会误导人：它确实会随着设置菜单光标变化，但它只是临时结构或栈上的菜单数据。没有读取者、写入者和保存链的交叉验证，不能把“附近会变化的字节”当成正式变量。

### 3. 优先找“已有调用点”，不要先改 ROM 或强控 CPU

攻击调用桥挂在游戏每帧都会经过的地图输入入口 `0x08018AF4`，原因是这里有稳定的原生调用栈。临时跳到 EWRAM 中的 mailbox bridge，完成后恢复原始 8 字节；没有命令时重放原入口指令。

这种做法有三个好处：可以沿用游戏自己的 ABI、随机数和动画状态；可以检查调用前后 SP 是否一致；实验失败时可以卸载补丁恢复现场。相反，直接从 Lua 改 PC/LR 或写 HP，虽然可能“看起来有效”，却无法证明调用约定和游戏状态是正确的，也容易在 VBlank 或存档恢复时失效。

### 4. 每个候选结论都要有“正向、反向、恢复”三种证据

本次没有只验证“写 1 会打开”。完整证据包括：

1. 正向：写 `0`/`1` 后，读取者进入不同原生函数，A/B 帧数明显不同；
2. 反向：设置菜单提交和保存/载入函数都指向同一个字节；
3. 恢复：卸载攻击桥、载回用户状态、再次读回开关，确认实验没有污染用户战局。

以后遇到类似“某个菜单选项的内存地址”问题，也应至少做到这三点。尤其是保存/载入后要重新读取，因为保存状态会覆盖运行时写入。

### 5. 先接受可能误判，再用更强证据推翻它

这次早期曾把 `0x0300756F` 当作动画开关，也曾依赖菜单按键去关闭演出。后续对照发现它只是临时菜单数据，才改为查找真正的 `ctx+0xC55`。这不是失败的旁支，而是逆向中的正常筛选过程：

- 只改地址后结果不稳定，说明它可能是临时副本；
- 菜单退出、保存或载入后地址被覆盖，说明它不是真正持久字段；
- 找到唯一读取者和分支后，才把地址升级为正式结论。

因此后续 agent 不应因为旧日志里有一个“看起来合理”的地址就继续沿用，应该优先相信最新的读写链和可重复 A/B 结果。

### 6. 面对同类 GBA 游戏的通用工作流

可以按下面顺序复用：

1. 做一个能稳定重现的存档，保存操作前后状态；
2. 记录最小可观测结果，不要先记录所有 RAM；
3. 每次只改一个菜单选项或一个输入，做差分扫描；
4. 对候选字节找 ROM 读取者和写入者，确认分支与调用参数；
5. 用 Ghidra 反编译调用点，标出 Thumb/ARM 状态、寄存器参数和栈参数；
6. 通过游戏现有调用点做可卸载的运行时实验；
7. 用相同存档做 A/B，比较结果、耗时和恢复状态；
8. 把“地址、证据、限制、恢复命令”一起写入交接文档。

地址本身只对当前 ROM 版本有效；可迁移的是这套证据链，而不是 `0x030010D5` 或 `0x08023188` 这些数字。

## 过程四：可重复的 A/B 验证

`tools/native_attack.py` 中的 `ANIMATIONTEST` 会：

1. 先保存用户当前战局到 `states/animation_user_before.State`；
2. 载入 `states/first_clear_start.State`，构造同一攻击起点；
3. 保存基线 `states/animation_ab_base.State`；
4. 分别设置 OFF、ON，各执行一次相同原生攻击并记录帧数、HP、弹药和行动状态；
5. 保存 `states/animation_off_verified.State` 和 `states/animation_on_verified.State`；
6. 写出 `logs/animation_ab.json`，最后载回用户原来的战局。

运行方式：

```powershell
python tools/native_attack.py ANIMATIONTEST
python tools/native_attack.py ANIMATION STATUS
python tools/native_attack.py ANIMATION OFF
python tools/native_attack.py ANIMATION ON
python tools/native_attack.py ANIMATION TOGGLE
```

命令通过 `shots/native_attack/command.txt` 与 Lua 文件握手，当前 GUI 运行时不需要关闭窗口。`ANIMATION` 的非法值会返回 `FAIL`，不会改变原值。

单独使用 BizHawk Lua Console 时，编辑 [lua/attack_animation_switch.lua](../lua/attack_animation_switch.lua) 顶部的 `MODE` 为 `OFF`、`ON`、`TOGGLE` 或 `STATUS`，运行一次即可。脚本会确认上下文为 `0x03000480` 并读回写入值。

## 当前现场和恢复点

本次测试结束时：

- 用户原战局已恢复到 `states/animation_user_before.State` 对应状态；
- 当前动画开关保持 ON（`0x030010D5 == 1`）；
- 当前可见 BizHawk 实例继续运行，窗口在正常 Windows 桌面；
- ROM 文件未修改；
- 代码桥在测试结束后已卸载；
- `lua/usa_ai_state.lua` 的启动逻辑已改为载入后直接写 `ctx+0xC55 = 0`，不再操作错误的 `0x0300756F` 设置临时变量。

重要文件：

```text
docs/ATTACK_ANIMATION.md                 动画开关说明
docs/NATIVE_ATTACK.md                    原生攻击桥说明
tools/native_attack.py                   构建桥、发送命令、执行 A/B 测试
lua/attack_animation_switch.lua          单次动画开关脚本
lua/native_attack.lua                    当前生成的实验 Lua
logs/animation_ab.json                   OFF/ON 对照结果
logs/animation_switch*.c                 Ghidra 静态证据
shots/native_attack/animation_*.gif      对照录像
```

## 后续 agent 接手时先做什么

1. 先查看 `docs/ATTACK_ANIMATION.md`、本文件和 `logs/animation_ab.json`。
2. 若要继续操作可见窗口，先确认 `shots/native_attack/emulator_pid.txt` 指向现有实例，再查看 `tools/window_diag.ps1 -Show` 输出。
3. 任何载入存档的动作之后重新读取 `0x030010D5`；保存/载入过程会覆盖运行时写入值。
4. 调试原生攻击时优先调用 `SNAP --full`，不要直接猜单位槽；`ATTACK` 要求单位已在合法射程内。
5. 不要把 `ctx+0x990` 当成选中单位槽，也不要把 `0x0300756F` 当成动画开关。
6. 尚未覆盖间接炮击、空海军、多目标武器、最后一击和投降确认框；若扩展攻击桥，应保留当前的 SP、mailbox、玩家阵营和 ROM 入口恢复检查。
