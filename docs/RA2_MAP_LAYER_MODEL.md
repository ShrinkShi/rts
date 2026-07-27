# RA2/YR 地图分层与高度数据模型

## v0.16.0-dev.2 的纠错

v0.15.0 把矿石同时当作：

- 地形类型 `TILE_ORE`
- 储量数组
- 独立 `OreEntity`

v0.16.0-dev.1 又把温带地形图集中的矿区方块完整绘制到实体层。这个方块与底层矿区 Tile 基本相同，因此即使节点已经位于地形上方，肉眼仍会认为矿石实体不可见。

dev.2 改为严格分层：

```text
Base Terrain
├── grass / dirt / road
├── water / coast
├── rock / cliff / ramp
└── Level / Slope / LandType

Overlay
├── TIB01..TIB20（矿石）
├── GEM01..GEM12（宝石）
├── walls
├── tracks
└── other overlays

Terrain Object
├── trees
├── rocks
└── decorations

Smudge
├── craters
└── scorch marks
```

矿石格现在保留草地或泥地作为底层，储量和 Overlay 图像独立保存。矿石耗尽只清除 Overlay 帧，不再篡改底层地形。

## GridWorld 新增字段

每个逻辑格现在至少保留：

- `terrain`
- `overlay_type`
- `overlay_frame`
- `height_level`
- `slope_type`
- `land_type`
- `ore_amount`
- `ore_capacity`

相关查询接口：

- `get_overlay_type(cell)`
- `get_overlay_frame(cell)`
- `get_overlay_asset_id(cell)`
- `get_height_level(cell)`
- `get_slope_type(cell)`
- `get_land_type(cell)`
- `get_ground_height(world_position)`
- `get_cell_snapshot(cell)`

目前 `height_level` 与 `slope_type` 只是数据基础。2D 矩形 TileMap 尚未根据高度移动或裁剪，不能把该阶段描述为“已经完成坡面和悬崖”。

## 矿石可见性回退

精确的 RA2 温带 Overlay 素材尚未进入公开仓库时，`OreEntity` 会绘制明显的像素矿堆，而不是再次绘制一个完整方形地形块。

该回退保证：

- 矿石可见。
- 与底层地形有清楚轮廓差异。
- 储量下降时矿堆密度下降。
- 耗尽时矿堆消失。
- 选择框和储量数字仍可用。

回退只是故障保护，不是最终素材。

## 最终 RA2 素材输入

温带矿石和宝石至少需要：

```text
TIB01.TEM ... TIB20.TEM
GEM01.TEM ... GEM12.TEM
ISOTEM.PAL
```

推荐直接提供完整提取包：

```text
ra2.zip
ra2md.zip
```

这样可以同时处理其他剧院的 Overlay、TerrainTypes、TMP、悬崖、坡面、水岸和桥梁资源，避免后续逐个索要文件。

## 转换命令

```bash
python tools/convert_ra2_overlays.py D:\RA2\extracted \
  --palette D:\RA2\extracted\cache\isotem.pal \
  --output assets/ra2_overlays/temperate \
  --strict
```

输出路径：

```text
assets/ra2_overlays/temperate/tib01.png
...
assets/ra2_overlays/temperate/tib20.png
assets/ra2_overlays/temperate/gem01.png
...
assets/ra2_overlays/temperate/gem12.png
assets/ra2_overlays/temperate/manifest.json
```

运行时按 `overlay_frame` 选择 `TIB01..TIB20`。当前映射将四个储量等级各分配五种确定性变体，避免每次重绘时随机跳图。

## 后续迁移

1. 导入原版 Overlay 素材并替换像素回退。
2. 把地图存储从程序化数组升级为可读写的等距单元结构。
3. 解析 `OverlayPack` 与 `OverlayDataPack`。
4. 解析 `IsoMapPack5` 的 TileIndex、SubIndex、Level。
5. 接入 TMP 坡面、悬崖、水岸和桥梁。
6. 寻路、建造、弹道、阴影和载具姿态统一读取高度与坡面数据。
