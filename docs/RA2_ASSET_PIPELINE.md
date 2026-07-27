# RA2 / 尤里的复仇素材管线

本工程支持把本地合法取得的 `SHP(TS)`、`VXL/HVA` 和 `WAV` 转换或导入为 Godot 4.7 可直接使用的资源。原始文件只用于本地开发，不应随公开仓库或发行包分发。

## 快速使用

### Godot 编辑器

1. 打开项目。
2. 顶部菜单选择“编辑器 → 管理编辑器功能”，确认 `RA2 Asset Importer` 已启用。
3. 右侧停靠栏打开“RA2 素材导入”。
4. 指定源目录、输出目录和 `ra2_import.json`。
5. 点击“扫描并导入全部素材”。

插件通过本机 Python 3 运行转换器，需要 Pillow：

```bash
python -m pip install -r tools/requirements.txt
```

Windows 也可以直接运行：

```text
import_ra2_assets_windows.bat
```

### 命令行

```bash
python tools/ra2_import.py --project-root . scan   assets/ra2_sources/samples   assets/ra2_imported   --config assets/ra2_sources/samples/ra2_import.json
```

## SHP(TS)

SHP 是调色板索引动画。转换时必须提供正确的 `.pal`，否则轮廓和透明度正确，但颜色可能不正确。输出包括：

- `atlas.png`
- `sprite_frames.tres`
- `shp_resource.tres`
- `metadata.json`

`ra2_import.json` 的 `states` 用于把原始帧编号映射到本引擎需要的 `stand_0`、`move_0`、`attack_0`、`death_0` 等动画。不同单位的帧布局不完全相同，不能假定一个映射适用于所有 SHP。

## VXL / HVA

- VXL 保存体素几何、颜色索引和法线索引。
- HVA 保存各部件逐帧变换。
- 车体、炮塔和炮管可以在配置中组合，也可以分别输出为 Godot `SpriteFrames`。
- 默认输出 8 个方向，并保留 HVA 的动画帧。

本转换器使用离线软件渲染生成透明 PNG。当前光照是近似实现；要严格复现原游戏，还需要对应的 VPL/法线查找表和完整渲染规则。

## WAV

WAV 被复制到 `assets/ra2_imported/audio/`，由 Godot 自身导入。可在脚本中使用：

```gdscript
var stream := RA2AssetLibrary.load_wav("res://assets/ra2_imported/audio/example.wav")
$AudioStreamPlayer.stream = stream
$AudioStreamPlayer.play()
```

## 配置示例

```json
{
  "default_palette": "unittem.pal",
  "shp": {
    "unit.shp": {
      "palette": "unittem.pal",
      "animations": {
        "states": {
          "stand": {"start": 0, "facings": 8, "frames_per_facing": 1},
          "move": {"start": 8, "facings": 8, "frames_per_facing": 6, "fps": 10}
        }
      }
    }
  },
  "vxl_groups": {
    "vehicle": {
      "body": "vehicle.vxl",
      "body_hva": "vehicle.hva",
      "turret": "vehicletur.vxl",
      "turret_hva": "vehicletur.hva",
      "barrel": "vehiclebarl.vxl",
      "barrel_hva": "vehiclebarl.hva",
      "facings": 8
    }
  }
}
```

## 与 Prefab 连接

- 步兵：把导出的 `sprite_frames.tres` 赋给单位场景的 `VisualRoot/Body`。
- 载具：车体使用 `body_frames.tres`，炮塔使用 `turret_frames.tres`。
- 建筑：在建筑根节点设置 `external_shp_resource` 及健康、受损、摧毁帧编号。
- 音效：把导入的 WAV 指定给 `AudioStreamPlayer`，或通过资源库加载。

示例预览场景：

```text
scenes/tools/ra2_asset_gallery.tscn
```

## 当前限制

1. 不解析 MIX 包，请先用外部工具解包。
2. SHP 不携带完整颜色信息，必须匹配正确 PAL。
3. VXL 光照目前不是原版像素级复刻。
4. 自动动画映射需要按具体单位配置，尤其是步兵死亡、特殊动作和建筑附属动画。
5. 转换器是开发期离线工具，不建议在正式游戏运行期间实时解析大型素材。
