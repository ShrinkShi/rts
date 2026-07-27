# RA2 / YR 资源浏览器使用说明

## 进入方式

运行项目后，在主菜单选择“RA2 / YR 资源数据库”。

## 单位与建筑

左侧可按步兵、载具、飞行器和建筑筛选。实心圆表示已经存在可播放预览，空心圆表示目前仅能查看数据和引用链。

中间预览区支持：

- 动画：切换 Ready、Walk、Fire、Die、Buildup、ActiveAnim 等动作。
- 方向：切换八方向或素材声明的其他方向数量。
- 剧院：切换温带、雪地、城市、沙漠、月球和新城市资源。
- 所属色：通过调色板索引遮罩切换玩家色。
- 上一帧、下一帧、播放、暂停、循环和速度。

右侧详情区显示 Rules ID、Art ID、素材文件、武器链、声音角色以及 INI 字段来源。

## 声音

单位页面的声音下拉框按角色列出其声音事件；“播放样本”播放当前样本，“随机事件”按原事件随机选择样本。

切换到左侧顶部的“声音事件”模式，可以搜索并试听完整声音目录。

所有 WAV 都通过 `AudioStreamWAV.load_from_file()` 从源文件读取。`assets/ra2_audio/.gdignore` 用于阻止编辑器为数千条语音生成 `.sample` 缓存，不影响本地运行时读取。

## 首次打开

预览 PNG 与音频目录均为运行时加载目录，正常情况下 Godot 不会导入三万余张 PNG 和数千个 WAV。若从旧版本覆盖升级，请关闭 Godot 并删除工程中的 `.godot/` 后重新导入。

## 重建预览

需要 Python 3 和 Pillow：

```bash
python tools/ra2_pipeline/preview.py \
  --ra2-root <RA2解包目录> \
  --ra2md-root <YR解包目录> \
  --database data/ra2/database.json \
  --output assets/ra2_preview \
  --extra expandmd01=<目录> \
  --extra expandmd03=<目录> \
  --extra expandmd04=<目录>
```

专用检查：

```bash
python tools/validate_v013_browser.py
```
