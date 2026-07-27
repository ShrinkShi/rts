# RA2/YR 本地化、音频和地图管线

## 1. 输入

完整重建脚本接受：

```text
ra2.zip
ra2md.zip
ra2.csf
ra2md.csf
audio.zip
audiomd.zip
expandmd01.zip
expandmd03.zip
expandmd04.zip
```

Windows 可直接运行：

```text
build_ra2_pipeline_windows.bat
```

也可以运行 `tools/ra2_pipeline/build_all.py` 并显式传入路径。

## 2. CSF 合并

合并优先级：

```text
ra2.csf < ra2md.csf
```

每个标签保留：

- 最终文本
- 来源层
- 全部历史值
- 可选的额外字符串

输出：

```text
data/ra2/localization.json
data/ra2/localization_catalog.json
```

实体不会丢弃原始 `UIName`，而是额外获得：

```json
{
  "display_name": "美國大兵",
  "localization": {
    "token": "Name:E1",
    "resolved": true,
    "text": "美國大兵"
  }
}
```

## 3. IDX/BAG 音频

`audio.idx` 负责样本名、偏移、长度、采样率和编码；`audio.bag` 保存裸音频数据。

管线不会把所有样本错误地当成 PCM，而是按格式码生成 WAV：

| 格式码 | 编码 |
|---|---|
| 6 | PCM 16-bit mono |
| 7 | PCM 16-bit stereo |
| 12 | IMA ADPCM mono |
| 13 | IMA ADPCM stereo |

输出：

```text
assets/ra2_audio/ra2/bag/*.wav
assets/ra2_audio/ra2/standalone/*.wav
assets/ra2_audio/ra2md/bag/*.wav
assets/ra2_audio/ra2md/standalone/*.wav
data/ra2/audio_manifest.json
data/ra2/sound_events.json
```

Godot 在首次导入工程时会将 WAV 转换为内部音频资源。`scripts/ra2/ra2_audio_library.gd` 提供按 Sound 事件加载随机样本的入口。

## 4. Sound 事件解析

`sound.ini/soundmd.ini` 中的 `Sounds=` token 会先移除 `$` 等控制前缀，再按大小写不敏感方式匹配样本名。

每个事件包含：

```text
sample_tokens       配置引用的全部样本名
samples             当前音频包中已找到的样本
missing_samples     未找到的样本名
raw_values          Control、Volume 等原始配置
```

缺失样本不会被静默删除，资源数据库会明确显示。

## 5. 扩展包覆盖

资源索引顺序：

```text
ra2
ra2md
expandmd01
expandmd03
expandmd04
```

后层同名文件覆盖前层；INI 字段仍保留具体来源层和历史。`expandmd02.zip` 为空包，因此没有加入有效来源列表。

## 6. 地图索引

地图文件复制到：

```text
assets/ra2_maps/
```

同时生成：

```text
data/ra2/maps_official.json
```

地图宽高从 `[Map] Size=x,y,width,height` 解析，而不是错误寻找通常不存在的 `Width/Height` 字段。索引还保留 `LocalSize`、剧院、路径点和 Trigger/TeamType/ScriptType/TaskForce 数量。

## 7. 双银行覆盖规则

当前同时接入 RA2 `audio.zip` 与 YR `audiomd.zip`。同名样本按以下优先级解析：

```text
RA2 audio < YR audiomd
```

两套物理文件都会保留，`audio_manifest.json` 记录来源银行、优先级及被覆盖历史。当前 `Sound` 配置引用的 1,825 个样本已全部解析，覆盖率为 100%。
