# v0.16.0-dev.9：RA2/YR 地图格式与温带剧院读取核心

日期：2026-07-30

## 目标

停止把程序化矩形地图伪装成 RA2 地图兼容层，改为以原始 `.map`、`.mpr`、`.yrm` 为唯一正式地图源，按原版字段读取 `IsoMapPack5`、`OverlayPack` 和温带 TMP 地形。

## 已完成

### 1. 地图容器读取

- 保序读取 Westwood INI。
- 支持重复键、未知节和原始节顺序。
- 解码 MiniLZO、Format5 和 Format80。
- 读取 `IsoMapPack5` 的 `X`、`Y`、`TileIndex`、`SubTileIndex`、`Level`、`IceGrowth`。
- 读取 `OverlayPack` 与 `OverlayDataPack`。
- 初步读取 Waypoints、Terrain、Structures、Units、Infantry、Aircraft、Smudge、Lighting。
- JSON 明确标记为可删除的运行缓存，不能替代原始地图。

### 2. Temperat.ini TileSet 目录

- 连续读取 `TileSet0000` 开始的剧院 TileSet。
- 按 `TilesInSet` 计算全局 `TileIndex` 范围。
- 将全局 `TileIndex` 精确解析为 TileSet 编号、TileSet 名称、组内序号和 TMP 文件名。
- 保留 `MarbleMadness`、`NonMarbleMadness`、`Morphable`、`ShadowCaster`、`AllowToPlace`、`AllowBurrowing`、`AllowTiberium`。

### 3. 温带资源归档栈

- 主资源优先读取 `IsoTemp`。
- 缺失内容继续读取可选 `Temperat`。
- 文件名不区分大小写。
- 运行缓存记录每个实际使用的 TMP 来自哪个归档。

### 4. TS/RA2 等距 TMP

已实现：

- TMP 文件头和子格指针表。
- 子格 X/Y。
- Main Image、ExtraData、ZData、ExtraZData。
- Height、TerrainType、RampType、RadarColor。
- HasExtraData、HasZData、HasDamagedData。
- 60×30 菱形索引图展开。
- 调色板 RGBA 诊断渲染。

TMP 子格中的数据偏移以当前子格头为基准，不是以整个文件为基准。

### 5. 地图与剧院联合导入

`ra2_map_importer.py` 新增：

```text
--theater-ini Temperat.ini
--theater-archive IsoTemp.zip
--theater-archive Temperat.zip
--theater-extension .tem
```

启用后，每条地图地形记录会额外获得：

- 原版 TMP 文件名。
- TileSet 编号和名称。
- TMP 块尺寸和子格位置。
- TMP Height、TerrainType、RampType。
- ExtraData 和 ZData 标志及尺寸。
- 实际资源归档来源。

地图 `Level` 与 TMP 内部 `Height` 分开保存，不混为一个字段。

## 用户提供文件的实测结果

使用本轮提供的 `mymap1.map`、`Temperat.ini`、`IsoTemp.zip`、`Temperat.zip`、`isotem.pal` 和 `unittem.pal`，得到：

- 地图尺寸：100×100。
- `IsoMapPack5`：19,900 条地形记录。
- Overlay：229 条。
- 温带 TileSet：82 组。
- 全局 TileIndex：838 个。
- 地图实际使用：67 个 TMP 文件。
- 所有实际使用的 `TileIndex + SubTileIndex` 均成功解析。
- 木桥 `ovrpsb01.tem` 不在 `IsoTemp.zip`，但在可选 `Temperat.zip` 中正确解析，证明双归档查找是必要的。

## 自动测试

新增测试覆盖：

- TMP 主图、ExtraData、ZData、ExtraZData。
- Height、TerrainType、RampType。
- 60×30 菱形展开的 900 个有效像素。
- 空子格拒绝。
- TileIndex 到 TMP 文件名的累计映射。
- IsoTemp + Temperat 可选资源查找。
- 地图 Level 与 TMP Height 分离。

## 当前边界

本阶段是读取核心，不是完整地图兼容完成版：

- 尚未把 60×30 等距 TMP 接入 Godot 主对局渲染器。
- 尚未按 ZData 和 ExtraZData 完成逐像素遮挡排序。
- 尚未把 TerrainType、RampType 和 Height 转换为正式通行网格。
- 尚未建立 Overlay ID 到矿石、围墙、桥梁等对象的完整规则表。
- 尚未实现地图写回和 Format5/MiniLZO 正式编码器。
- 尚未进行 Final Alert 2 / WorldAlteringEditor 往返保存验证。

## 下一步

1. 建立 60×30 RA2 等距地图运行时坐标系。
2. 按原始 `TileIndex + SubTileIndex + Level` 绘制 TMP。
3. 接入 Main Image、ExtraData、ZData、ExtraZData 排序。
4. 用 TerrainType 和 RampType 建立通行与坡道连接。
5. 读取 Overlay 规则并恢复矿石、矿柱、桥梁、围墙。
