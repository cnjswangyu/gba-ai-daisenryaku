# 攻击动画开关：直接内存控制

已对项目的《大战略》ROM做静态逆向及同存档攻击对照。真正开关为单字节 **`0x030010D5`**，即游戏上下文 `0x03000480 + 0xC55`。

```lua
memory.write_u8(0x030010D5, 0) -- 关闭完整战斗演出，使用简化显示
memory.write_u8(0x030010D5, 1) -- 开启完整战斗演出
```

在战场待命时写入即可，下次攻击生效。切换无需按键、菜单或代码补丁。模拟器继续显示战场；关闭完整演出仍有简化效果。

## 使用方法

通用的单次脚本是 [lua/attack_animation_switch.lua](../lua/attack_animation_switch.lua)。将顶部 `MODE` 改为 `OFF`、`ON`、`TOGGLE` 或 `STATUS`，在 BizHawk Lua Console 中运行。脚本会检查游戏上下文并读回确认。

已有 `Start-Native-Attack.cmd` 启动的实验实例时，也可在项目目录运行：

```powershell
python tools/native_attack.py ANIMATION OFF
python tools/native_attack.py ANIMATION ON
python tools/native_attack.py ANIMATION STATUS
python tools/native_attack.py ANIMATION TOGGLE
```

游戏设置及模拟器存档会保存、恢复这个值。因此需要在载入后再切换；这里不持续锁定内存。主 AI 脚本 `lua/usa_ai_state.lua` 已改为载入后直接关闭完整演出。

## 原生代码证据

| 位置 | 行为 |
|---|---|
| `0x08022BE8` | 战斗流程读取 `ctx+0xC55`，严格比较是否等于 1 |
| `0x08025C98` | 值为 1：完整战斗演出 |
| `0x08026000` | 其他值：简化显示；正常关闭应写 0 |
| `0x0801AAAC` | 设置菜单第三行左右切换临时结构 `+3`；A 提交，B 取消 |
| `0x0801A9D4` | 指令字节 `0A 70`，将菜单设置写到实际开关 |
| `0x08000272` | 初始化默认写 1 |
| `0x0800170E` | 从游戏保存缓冲 `+0x14` 恢复设置 |
| `0x080017CE` | 将设置保存到缓冲 `+0x14` |

旧记录的 `0x0300756F` 属于设置菜单临时数据，不能作为稳定的战场开关。历史文档中“必须走设置界面”“直接写 0 无效”的结论已推翻。

反编译证据在 `logs/animation_switch.c`、`logs/animation_switch_menu.c`、`logs/animation_switch_save.c`，由本地 Ghidra 分析生成。

## 同存档实测

从相同状态开始，M1A2 对相邻 T-72B 执行相同原生攻击，仅改变开关：

| 设置 | 原生战斗调用耗时 | 我方 HP | 敌方 HP | 我方弹药 | 反击弹药 | 已行动 |
|---|---:|---|---|---|---|---|
| OFF（0） | 201 帧 | 16→13 | 12→8 | 4→3 | 1→0 | true |
| ON（1） | 501 帧 | 16→13 | 12→8 | 4→3 | 1→0 | true |

这里记录模拟器帧数，不是工具执行的墙钟时间；演出差 300 帧。该组实验的结算结果一致。

实验命令 `python tools/native_attack.py ANIMATIONTEST` 会暂存当前战局，载入测试战场做两次攻击，正常完成后恢复当前战局。运行时不要手动输入；该命令仅在战场待命时使用。结果：`logs/animation_ab.json`；录像：`shots/native_attack/animation_off.gif`、`animation_on.gif`；原局备份：`states/animation_user_before.State`。

另外实测了 OFF/ON/TOGGLE/STATUS 的读回，非法模式被拒绝且原值不变。ROM 文件未修改。
