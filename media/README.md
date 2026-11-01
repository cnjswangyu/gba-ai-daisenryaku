# Media

| 文件 | 来源 |
|---|---|
| `victory_native.png` | BizHawk `client.screenshot()` 原生 240×160，2026-11-01 air-supply 通关 |
| `victory_4x.png` | 上面的 4× 最近邻放大（960×640） |
| `full_combat.gif` | `shots/native_attack/` 录制的原生战斗帧，720×480，10 fps |
| `trajectory_u0.png` | `media/trajectory.html` 第 16 回合、单看 U0 直升机的补给往返 |
| `trajectory_t8.png` | 同一页面第 8 回合、双方全部单位 |
| `trajectory.html` | 2026-11-01 air-supply 战局的可交互轨迹（自包含，无外部依赖） |
| `highlight.mp4` | 片头卡 + 第 2/3 回合战斗片段 + 胜利结算，720×480，H.264 |

`highlight.mp4` 由 `tools/make_release_video.py` 从 `shots/first_clear/frames/`
的原始帧重新编码生成；截图与 GIF 均来自模拟器自身输出，没有后期合成战斗画面。

文档与媒体为 CC BY 4.0，转载注明出处。
