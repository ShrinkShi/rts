# v0.16.0-dev.10：RA2/YR 原始地图运行时接入

## 目标

停止在 32×32 程序化矩形地图上继续贴原版图块，改为以 `.map/.mpr/.yrm` 为唯一可编辑源，并由以下数据生成 Godot 运行缓存：

- `IsoMapPack5`
- `OverlayPack` / `OverlayDataPack`
- `Temperat.ini`
- 原版温带 TMP
- `isotem.pal`
- `temperat.pal`
- `unittem.pal`

运行缓存可以删除和重建，不替代原始地图，也不写回伪造的 RA2 地图数据。

## 本轮修复的断点

上一次中断时，开发分支已经存在 60×30 等距运行时脚本和一份清单，但该分支不可运行：

- `data/maps_ra2.json` 指向不存在的 `mymap1_runtime_v2.json`。
- 清单引用的 `mymap1_cells_*.b64` 和 `mymap1_terrain_*.b64` 未提交。
- 纠正矿石调色板所需的 `temperate_resources_v2_*.b64` 未提交。
- 单元解码在设置 `valid_cells` 前调用 `_inside()`，导致所有单元都被当作无效格跳过。
- 运行时只接受 WebP，没有定义可复现、无额外依赖的无损输出格式。
- 旧硬编码图集布局无法验证资源帧与调色板来源。

本轮不再用不存在的文件名掩盖这些问题。

## 新增工具链

### `tools/build_ra2_runtime_bundle.py`

从原始地图和剧院资源一次性构建：

- 60×30 等距地形 PNG。
- 精确地形单元缓存：`rx`、`ry`、`level`、`terrain_type`、`ramp_type`。
- 矿石和宝石 Overlay 缓存。
- 原版 TIB/GEM/TIBTRE 图集。
- 地图运行时清单。
- 原始文件 SHA-256 来源记录。
- `data/maps_ra2.json` 条目。

示例：

```bash
python tools/build_ra2_runtime_bundle.py mymap1.map \
  --theater-ini Temperat.ini \
  --isotemp IsoTemp.zip \
  --temperat Temperat.zip \
  --isotem-palette isotem.pal \
  --temperat-palette temperat.pal \
  --unittem-palette unittem.pal \
  --project-root . \
  --map-id ra2_mymap1 \
  --map-name "温带测试地图（RA2原图）" \
  --force-disable-fog
```

### `tools/ra2_shp_ts.py`

新增 Westwood SHP(TS) 读取器：

- 文件头和帧表。
- 未压缩帧。
- 逐扫描线 RLE。
- 透明游程。
- 帧偏移与画布合成。
- 索引色到 RGBA 转换。

### `tools/validate_ra2_runtime_bundle.py`

验证：

- 所有清单引用文件存在。
- Base64 可解码。
- 记录长度与数量匹配。
- PNG 格式、尺寸和 SHA-256 匹配。
- 矿石图集至少包含 `TIB01` 到 `TIB20` 的边界帧和矿柱动画边界帧。
- 调色板规则固定为：
  - `TIB*.TEM` / `GEM*.TEM` → `temperat.pal`
  - `TIBTRE*.TEM` → `unittem.pal`

## Godot 运行时

- 修复 `valid_cells` 初始化死锁。
- 运行时清单升级为 `ra2-godot-runtime-v2`。
- 地形背景支持无损 PNG，并检查实际尺寸与清单一致。
- 60×30 菱形坐标和高度反算使用实际 `height_step`。
- 建筑禁止放在坡面、不同高度、矿石、树木、水面和岩地上。
- 矿石根据源 Overlay ID 使用 `tib_##_##` 或 `gem_##_##`。
- 纠正后的资源图集改为清单驱动，不再依赖硬编码槽位。
- 运行缓存或纠正资源图集缺失时，RA2 地图不会出现在遭遇战列表中，避免玩家进入半成品地图。

## 当前验证状态

已完成：

- Python 语法检查。
- SHP 未压缩与 RLE 合成测试。
- PNG 编码、透明混合和 Base64 分块测试。
- 运行清单与资源清单的合成数据验证测试。

尚未完成：

- 用用户原始 `mymap1.map`、剧院 ZIP 和三份 PAL 构建并提交实际缓存。
- Godot 4.7.1 Parser 与 F5 实机验证。
- 原版 ZData/ExtraZData 与单位、悬崖之间的完整遮挡交错。
- `.map` 写回以及 Final Alert 2 / World-Altering Editor 往返保存。

因此本分支必须保持 Draft，不能宣称已经完成“完全兼容 RA2 地图”。
