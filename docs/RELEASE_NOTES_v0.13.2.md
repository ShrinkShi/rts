# Iron Meridian RTS v0.13.2 — RA2/YR 组合素材修复

本版本是 v0.13.1 的增量修复，集中处理 VXL/HVA 多部件模型、建筑 SHP 组合、可通行 Bib、受损/阴影帧分离以及建筑炮塔。

## 修复

- HVA 平移按 VXL section scale 转换，修复盖特坦克和武装直升机部件分离。
- Art 动画帧范围支持 `End`、`Reverse`、`Shadow`、`DoubleThick` 等字段。
- `LoopEnd` 按循环终点处理，正常帧不再越界进入受损帧。
- SHP 阴影帧库不再进入正常动画；Buildup 也会剥离后半段阴影库。
- 建筑合成加入 `BibShape`、门、屋顶门、部署部件等结构层。
- 空壳/分件建筑会从 SpecialAnim 或 SuperAnim 选择完整静态状态，生成 `Ready` 与 `DamagedReady`。
- 超级武器的多个完整状态 SHP 不再错误叠加成离散碎片。
- 建筑 VXL 炮塔按主体边界、Rules X/Y 偏移重新定位，并采用等距朝向。
- 建筑默认预览优先使用 `Operational`，无工作动画时使用包含炮塔和持久部件的 `Ready`。

## 针对性复核对象

- YAGGUN、YTNK、SCHP
- GAREFN、NAREFN、YAREFN
- GADEPT、NADEPT、CAOUTP
- GAWEAP、NAWEAP、YAWEAP
- NALASR、NASAM、GTGCAN、NAFLAK
- NATBNK、YAPPET、YAGNTC、NAMISL、GACSPH
- GAAIRC、AMRADR、YAGRND
- NACNST、YACNST、YAPOWR、YAPSYT

## 说明

当前 VXL 预览仍是软件等距渲染器，不等于原版 TS/RA2 voxel renderer 的像素级光照结果；本次目标是正确组合、方向、位置和状态隔离。预览缓存继续作为开发验证素材，后续运行时会逐步改为数据驱动实体渲染。
