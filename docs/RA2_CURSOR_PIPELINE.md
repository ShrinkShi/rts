# RA2/YR 鼠标光标管线

## 输入与验证

本阶段使用用户提供的：

- `mouse.shp`
- `mousepal.pal`

已验证：

- SHP(TS) 画布为 55×43。
- 原文件共 450 帧。
- 449 帧为透明、未使用 RLE 的索引图像，另有 1 个空帧。
- `mousepal.pal` 为 768 字节 Westwood 6 位 RGB 调色板。

原始 SHP 和 PAL 不提交到公开仓库。它们只作为本地转换输入。

## 运行时文件

- `scripts/ra2/ra2_cursor_manager.gd`
- `scripts/ra2/cursor_chunks/frame_00.gd` 至 `frame_09.gd`
- `scripts/ra2/cursor_chunks/palette.gd`

当前运行时只打包游戏现有状态实际使用的 63 个源帧。转换器保留每像素的 8 位调色板索引，将这些索引连续拼接后使用 zlib/DEFLATE 压缩，再切分为十段 Base64 文本。调色板同样以 Base64 文本保存。

`RA2CursorManager` 启动时：

1. 合并十段压缩数据。
2. 使用 `FileAccess.COMPRESSION_DEFLATE` 解压索引帧。
3. 将 6 位 RGB 调色板扩展为 8 位 RGB。
4. 将索引 0 作为透明色，重建 55×43 `ImageTexture`。
5. 按状态保存帧序列、动画速率和独立 hotspot。
6. 使用 `PROCESS_MODE_ALWAYS` 推进动画，暂停菜单不会冻结光标。
7. 解码失败时恢复操作系统默认箭头，并输出明确警告。

## 已接入现有游戏状态

- `default`
- `select`
- `selected`
- `move`
- `attack`
- `enemy`
- `build_valid`
- `build_invalid`
- `pan`
- `primary`

数据中同时保留八方向地图边缘滚动状态，后续由战场边界检测接入：

- `edge_n`
- `edge_ne`
- `edge_e`
- `edge_se`
- `edge_s`
- `edge_sw`
- `edge_w`
- `edge_nw`

## 重新检查原始素材

```bash
python tools/convert_mouse_shp.py mouse.shp \
  --palette mousepal.pal \
  --output .ra2_cache/mouse_frames
```

该工具输出 450 张透明 PNG 和 `frames.json`，用于人工核对帧内容。它不会自动改写运行时 chunk；运行时数据更新必须经过帧区间复核，避免把未知帧错误映射成命令光标。

## 当前边界

- v0.16.0-dev.1 只替换现有 `CursorManager` 已经使用的状态。
- 维修、出售、进入、攻击移动、部署等光标需要在对应命令模式接入后再启用。
- 八方向地图滚动帧已打包，但尚未与屏幕边缘方向联动。
- 当前环境没有 Godot 4.7.1 可执行文件，尚未完成编辑器解析和 F5 对局验证。

## 本机验收

必须检查：

- 默认箭头热点位于左上尖端。
- 选择、移动、攻击光标中心与鼠标命中点一致。
- 动画在暂停菜单中继续播放。
- 切换状态时从第一帧开始。
- UI 区域恢复默认箭头。
- 空选时长按右键拖动画面显示 `pan` 光标。
- 建筑可放置和不可放置光标能正确区分。
- 关闭或破坏任意 chunk 后，工程不崩溃并回退操作系统光标。
