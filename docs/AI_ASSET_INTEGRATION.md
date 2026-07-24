# AI 高精度素材接入说明 v0.8.4

## 运行时图集

| 图集 | 布局 | 单帧尺寸 | 用途 |
|---|---:|---:|---|
| `units/rifle.png` | 8×5 | 128×128 | 八方向静止、两帧移动、开火、死亡 |
| `units/tank_chassis.png` | 8×3 | 224×192 | 八方向底盘静止和两帧履带移动 |
| `units/tank_turret.png` | 8×2 | 224×192 | 八方向独立炮塔瞄准与开火 |
| `units/tank_death.png` | 8×1 | 224×192 | 八方向坦克残骸 |
| `buildings/power.png` | 3×3 | 256×224 | 建造、完整、两级受损和废墟 |
| `buildings/barracks.png` | 3×3 | 256×224 | 建造、完整、两级受损和废墟 |
| `buildings/refinery.png` | 4×3 | 256×224 | 建造、完整、卸矿、受损和废墟 |
| `buildings/turret_base.png` | 3×3 | 256×224 | 防御炮塔固定基座 |
| `buildings/turret_head.png` | 8×2 | 192×160 | 防御炮塔独立旋转炮头 |
| `buildings/bunker_base.png` | 3×3 | 256×224 | 机枪碉堡固定基座 |
| `buildings/bunker_head.png` | 8×2 | 160×144 | 碉堡独立旋转机枪模块 |

## 方向约定

为了让PNG文件可以直接人工检查，AI方向图集从左到右固定为：

```text
上、左上、左、左下、下、右下、右、右上
```

Godot逻辑方向索引仍按屏幕坐标角度排列：

```text
0 右、1 右下、2 下、3 左下、4 左、5 左上、6 上、7 右上
```

`SpriteSheetFactory.AI_ATLAS_COLUMN_BY_ENGINE_DIRECTION` 负责两者转换。坦克底盘方向由移动速度决定；炮塔方向由攻击目标或强制攻击点决定。没有目标时炮塔跟随底盘方向。

## 队伍色

源图以蓝色为标准阵营色。`shaders/team_tint.gdshader` 仅识别蓝色占优区域并替换为玩家所属色，灰色金属、黑色履带、火焰和烟雾不会被整体染色。

## 再处理

AI 原始源图保存在：

```text
assets/ai_generated/source_sheets/
```

执行：

```bash
python tools/process_ai_assets.py
```

脚本会完成：灰色背景估计与透明化、边缘清理、方向重排、统一画布尺寸和运行时图集输出。
