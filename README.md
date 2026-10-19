# 时之沙 · 6 人沙漠卡丁车道具赛 Demo (Sands Kart Demo)

用 **Godot 4 + GDScript** 做的单局卡丁车道具赛 demo：你驾驶一辆卡通卡丁车，和 5 个带弹性追赶的 AI 在一条仿「时之沙」的单程沙漠赛道（约 2.9 km）上竞速，规则参考 QQ 飞车道具赛：道具箱拿氮气 / 攻击道具，漂移出弯接小喷（支持双喷），起步喷、空喷、落地喷。

> ⚠️ 美术全部是**程序化生成的占位简模**（方块/圆柱/球体拼的卡丁车、建筑、石柱、拱门、仙人掌、棕榈树、岩石，噪声高度图沙丘），没有使用任何外部模型或素材。音频暂未实现。

## 操作

| 按键 | 动作 (InputMap action) |
|---|---|
| W / ↑ | 加速 `throttle` / `move_forward`（漂移松开后 0.3 秒内再按 = 小喷；GO 瞬间按住 = 起步喷；空中按 = 空喷；落地瞬间按 = 落地喷） |
| S / ↓ | 刹车 / 倒车 `brake` / `move_backward` |
| A D / ← → | 转向 `steer_left` / `steer_right` |
| Shift | 漂移 `drift` |
| Ctrl / Space | 使用道具 `use_item`（2 个道具格） |
| R | 重生 `respawn`（回到赛道，罚时 3 秒） |
| Esc | 暂停 `pause` |

## 运行

1. 下载 [Godot 4.7.x 标准版](https://godotengine.org/download)（非 Mono 版即可，开发时使用 4.7.2-stable）。
2. 用 Godot 打开本目录的 `project.godot`，按 F5 运行（主场景 `res://scenes/main.tscn`）。
3. 命令行：`godot --path . `；直接进比赛：`godot --path . res://scenes/race/race.tscn`

可选参数（放在 `--` 之后）：`--autopilot`（玩家车由 AI 代驾）、`--laps=1`、`--test`。

### 无头测试

```bash
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test
```
结果写入 `tests/test_results.json`。

### 重新生成赛道

```bash
python3 tools/track_builder.py   # 需要 numpy；输出 data/track_data.json + data/terrain_height.bin
```

## 目录

- `scenes/` 主场景、比赛、卡丁车、赛道、UI、8 种道具
- `scripts/` 车辆物理、玩家输入、AI 驾驶、弹性追赶、比赛/排名、道具、HUD、检查点
- `data/` `kart_config.tres`（车辆参数）、`item_table.tres`（道具权重）、赛道烘焙数据
- `tools/track_builder.py` 按 A–G 路段（直线长度 / 弯道半径）烘焙赛道中心线、高度、加速带、道具箱、装饰物和沙丘高度图
- `tests/` 无头功能测试和截图脚本

## 状态 / 路线图

- [x] 工程初始化 + InputMap
- [x] 车辆物理（贴地、漂移、小喷/双喷、起步喷、空喷/落地喷、buff 取最大）
- [x] 赛道构建（A 起始加速带 → B → C 沙漠小镇 → D/E 沙丘 → F 终点段 → G 冲线）
- [x] AI 驾驶 + 性格 + 宿敌 + 弹性追赶
- [x] 8 种道具 + 按名次权重分配
- [x] 排名 / 检查点 / 逆行 / 比赛流程
- [x] HUD + 小地图
- [ ] 正式美术模型、音效与 BGM
- [ ] 手柄支持、更多赛道

---

**English:** A small Godot 4 (GDScript) kart item-racing demo: you vs 5 rubber-banded AI karts on a single-run ~2.9 km desert track inspired by "Sands of Time" from QQ Speed. Drift + mini-boost (incl. double boost), start/air/landing boosts, 8 items with rank-weighted odds, live ranking, wrong-way warning, HUD with minimap, title → 3-2-1-GO → race → results loop. All art is procedural placeholder geometry. Open `project.godot` with Godot 4.7.x (standard build) and press F5. License: MIT.
