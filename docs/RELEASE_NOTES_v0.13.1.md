# Iron Meridian RTS v0.13.1

本补丁针对 v0.13.0 资源浏览器的 SHP 方向、建筑组合动画和剧院素材选择进行修复。

## 修复

- 步兵与恐怖机器人等 SHP 载具的八方向顺序改为 RA2/YR 实际帧序：`N, NW, W, SW, S, SE, E, NE`。
- Godot 方向继续使用 `E, SE, S, SW, W, NW, N, NE`，二者映射为 `6,5,4,3,2,1,0,7`。
- VXL/HVA 载具使用独立投影方向，不受此次 SHP 修复影响。
- `NewTheater=yes` 的资源候选顺序改为“当前剧院字母 → G 通用版本 → 原始注册名”，避免温带错误回退到 A（雪地）素材。
- 建筑预览提供温带与雪地切换。温带优先使用第二字符为 `T` 的素材；若不存在则使用 `G` 通用素材，雪地使用 `A` 素材。
- 建筑的 `ActiveAnim`、`ActiveAnimTwo/Three/Four`、`IdleAnim` 等工作部件不再分开显示，改为与主体 SHP 合并成 `Operational` 动画。
- 受损主体与各 `*Damaged` 部件合并成 `DamagedOperational` 动画。
- 解析并保留组件的 `X`、`Y`、`ZAdjust`、`YSort`、`Powered` 等父级 Art 参数。
- 对包含整栋建筑画面的动画 SHP 自动提取动态像素区域，避免多个完整画面互相覆盖；局部动画 SHP 仍按透明图层直接合成。
- 补充 `ActiveAnimFour`、`IdleAnimTwo`、门、屋顶、部署、超级武器等受损组件的索引支持。

## 验证

- E1 与 DRON 八方向源帧映射回归测试通过。
- HTNK VXL 方向管线保持不变。
- GAPOWR 温带解析为 `ggpowr.shp`，雪地解析为 `gapowr.shp`。
- GAWEAP 完整工作动画同时包含 `ActiveAnim` 与 `ActiveAnimTwo`。
- 所有 manifest 引用的基础帧与所属色遮罩均存在。
