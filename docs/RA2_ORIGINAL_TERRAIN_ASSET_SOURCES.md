# RA2 原版温带资源来源与转换说明

## 本轮输入

用户提供：

- `ra2(1).zip`
- `ra2md(1).zip`

## 已接入资源

| 运行时用途 | 原文件 | 调色板 | 当前状态 |
|---|---|---|---|
| 普通矿石 | `temperat/TIB*.TEM` | `cache/ISOTEM.PAL` | 已接入 12 个图像 |
| 矿柱 | `temperat/TIBTRE01.TEM` | `cache/ISOTEM.PAL` | 已接入 11 帧 |
| 温带水面 | `isotemp/WATER01.TEM`–`WATER14.TEM` | `cache/ISOTEM.PAL` | 已接入 |
| 温带岸线 | `isotemp/SHORE*.TEM` | `cache/ISOTEM.PAL` | 已接入四方向邻接所需子集 |
| 苏联哨戒炮 | 仓库既有 `nglasr.shp` 提取预览 | 建筑预览既有调色流程 | 恢复原版合成帧 |

## TMP 解码范围

本轮使用 TMP(TS) 单格图像中的：

- 主菱形等距像素。
- 附加图像像素和偏移。
- `ISOTEM.PAL` 颜色索引。

透明色索引 0 不绘制。

## 当前适配方式

RA2 原版 TMP 主菱形尺寸为 60×30，而当前项目底层仍是 32×32 矩形 TileMap。运行时图集保留原版像素，再按当前逻辑格进行缩放和重叠绘制。

因此当前成果是“原版资源接入现有底座”，不是完整的 RA2 等距地图重构。后续仍需：

1. 使用真正的等距坐标和高度层。
2. 解析 TileSet 编号与 SubTile 组合。
3. 接入全部岸线、悬崖、坡道、道路和桥梁组合。
4. 加载 `IsoMapPack5` 与 Overlay 数据。
