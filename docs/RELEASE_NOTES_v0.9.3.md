# v0.9.3 RA2/YR 素材兼容层

- 新增 SHP(TS) 解析器，支持原始帧和行 RLE 帧。
- 新增 PAL 调色板加载与 VXL 内嵌调色板回退。
- 新增 VXL 体素解析、HVA 部件动画解析和 8 方向离线渲染。
- 支持车体、炮塔、炮管分层输出，保持现有独立炮塔战斗逻辑。
- 新增 WAV 复制与 Godot 原生音频资源加载。
- 新增 Godot 编辑器停靠栏和 Windows 一键导入脚本。
- GGI、HTK、YGPOWR 已作为本地测试样例接入步兵、坦克和发电站 Prefab。
- 新增 `scenes/tools/ra2_asset_gallery.tscn` 和完整管线文档。

## 注意

示例 SHP 暂时使用 HTK VXL 的内嵌调色板作为回退，因此颜色仅用于验证解码和动画逻辑。换入对应 RA2/YR PAL 后重新导入，才会得到正确颜色。
