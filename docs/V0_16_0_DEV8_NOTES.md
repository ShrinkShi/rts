# v0.16.0-dev.8：原版温带矿石、水面、矿柱与经济单位规则

日期：2026-07-29  
基础版本：v0.16.0-dev.7 Hotfix 2

## 资源来源

本轮直接使用用户提供的原版资源包：

- `ra2(1).zip`
- `ra2md(1).zip`

从中读取并转换：

- `cache/isotem.pal`
- `temperat/tib*.tem`
- `temperat/tibtre01.tem`
- `isotemp/water*.tem`
- `isotemp/shore*.tem`

转换结果压缩为一个运行时 PNG 图集，通过四段 Base64 文本存入仓库。游戏启动后只解码一次，并按资源 ID 创建 `AtlasTexture`，避免提交大量零散 PNG。

## 1. 原版 RA2 矿石

- 矿石实体改用原版温带 `TIB` TMP 像素。
- 当前图集包含 12 个可见储量阶段/变体。
- 储量降低时会切换为较稀疏的原版矿石图像。
- 原版图集无法加载时仍保留简单可见回退，防止资源逻辑存在但画面完全不可见。

## 2. 原版矿柱与矿石扩散

- 新增矿柱实体，使用 `TIBTRE01.TEM` 的 11 帧动画。
- 每张带矿区的地图默认生成 1 至 4 个矿柱，也可使用 `ore_pillar_count` 显式指定。
- 矿柱约每 8.5 至 13.4 秒尝试在附近扩散一次矿石。
- 每次增加 150 储量，单格上限为 1800。
- 不会生成到：
  - 水面。
  - 岩石。
  - 建筑占用格。
  - 树木格。
  - 其他矿柱格。
  - 不同高度层。
- 矿柱自身阻挡步兵和车辆，不能被采集或摧毁。

## 3. 原版水面和陆水交界

- 新增 `RA2OriginalWaterOverlay`。
- 水面使用 `WATER01.TEM` 至 `WATER14.TEM`。
- 岸线根据上、右、下、左四向陆地邻接掩码选择 `SHORE*.TEM`。
- 保留旧水面地块作为底层无缝填充，原版菱形 TMP 覆盖层负责主要视觉。
- 新增地图 `temperate_coast_trial / 温带海岸试验场`，用于验证水面、岸线、陆地寻路和矿柱扩散。

当前限制：项目底层仍是 32×32 矩形网格。原版 60×30 菱形 TMP 被适配到现有网格，因此属于原版素材接入，不等于已完成 RA2 等距地图坐标重构。

## 4. 苏联哨戒炮恢复原版素材

- 删除运行时手绘炮塔方案。
- `NALASR` 重新使用仓库中从 `nglasr.shp` 提取的原版 `Ready` 和 `DamagedReady` 合成帧。
- 运行时不再创建 `SentryGunVisual` 手绘炮头。
- 原版预览宽度恢复为 44 px，地面锚点恢复为 7 px。

## 5. 苏联武装采矿车

### AI 角色

- 武装采矿车保留武器与自卫能力。
- 战略角色明确为 `economy`。
- AI 进攻波和基地局部响应均排除所有采矿车。
- 采矿车不再计入 AI 可用进攻军力。

### 朝向

- 苏联 `HARV` 车体方向增加 4 个八方向索引偏移，即 180° 校正。
- 炮塔方向仍独立使用目标朝向，不随车体翻转。
- 只修正苏联武装采矿车，不影响盟军超时空采矿车与尤里奴隶矿场载具。

## 6. 电力显示

右上角统一显示：

```text
当前用电量 / 总发电量
```

最终颜色规则：

- 负载率 `<= 75%`：绿色。
- 负载率 `> 75% 且 <= 100%`：黄色。
- 负载率 `> 100%`：红色。
- 总发电量为 0 且存在耗电时：红色超负荷。

新增最终显示所有者 `RuntimePowerDisplayRules`，以最高界面刷新优先级在渲染前统一文本和颜色，阻止旧显示顺序与新显示顺序交替闪烁。

## 7. 工程结构

新增：

- `scripts/ra2/ra2_original_texture_library.gd`
- `scripts/game/ra2_water_overlay.gd`
- `scripts/game/ore_pillar_entity.gd`
- `scripts/core/runtime_ra2_resource_rules.gd`
- `scripts/core/runtime_harvester_rules.gd`
- `scripts/core/runtime_power_display_rules.gd`
- `data/ra2_embedded/temperate_runtime_atlas.json`
- `data/ra2_embedded/temperate_runtime_atlas_00.b64` 至 `_03.b64`

修改：

- `scripts/game/ore_entity.gd`
- `scripts/game/ai_controller.gd`
- `scripts/core/runtime_sentry_visual_rules.gd`
- `data/ra2/runtime_profiles.json`
- `data/maps_height.json`
- `project.godot`
- `BUILD_INFO.json`
- `tools/validate_project.py`

## 8. 明确边界

- 本轮没有接入所有 20 个 `TIB` 与 12 个 `GEM` 资源，目前优先完成普通矿石的可玩链路。
- 水岸当前使用四方向邻接选择，尚未覆盖原版所有复杂内角、外角和多格岸线组合。
- 水面目前影响陆地单位通行，但还没有海军、两栖单位、水波尾迹和桥梁系统。
- 树木原版化尚未进入本轮运行时图集。
- 原版悬崖和坡道 TMP 尚未替换 dev.7 的程序化悬崖表现。
- 尚未在 Godot 4.7.1 中完成 Parser、F5 对局和性能验证。

## 9. 实机测试清单

1. 检查工程导入是否出现 Parser Error。
2. 检查普通地图矿石是否使用黄色原版 RA2 TIB 图像。
3. 观察矿石储量下降时图像是否逐渐稀疏。
4. 观察矿柱动画和周围矿石扩散至少两分钟。
5. 确认矿石不会扩散到水里、建筑、树木或不同高度层。
6. 进入“温带海岸试验场”，检查水面和岸线连接。
7. 确认步兵和车辆不能进入水面。
8. 检查苏联哨戒炮是否恢复原版 SHP 合成画面。
9. 检查苏联采矿车前进方向是否正确，炮塔是否仍能独立瞄准。
10. 观察 AI 进攻波，确认武装采矿车继续采矿且不随军进攻。
11. 建造/出售发电设施与耗电建筑，确认电力始终显示为“耗电/发电”。
12. 检查 75%、100% 两个阈值附近是否正确切换绿、黄、红且不闪烁。
13. 记录普通地图、海岸地图和大量矿石扩散后的 FPS。
