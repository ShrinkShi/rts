# Godot 可视化预制场景工作流（v0.9.1）

本版不再把单位和建筑的视觉节点完全通过代码动态创建。每一种实体都有真实的 `.tscn` 场景，Godot 编辑器打开后能直接看到精灵、炮塔、碰撞体和挂点。

## 入口

单位：

- `scenes/entities/units/rifle.tscn`
- `scenes/entities/units/rocket.tscn`
- `scenes/entities/units/tank.tscn`
- `scenes/entities/units/scout.tscn`
- `scenes/entities/units/harvester.tscn`

建筑：

- `scenes/entities/buildings/command.tscn`
- `scenes/entities/buildings/war_factory.tscn`
- `scenes/entities/buildings/repair_bay.tscn`
- 其余建筑位于同一目录。

总览：`scenes/tools/prefab_gallery.tscn`。

## 调整方式

以采矿车为例，双击 `harvester.tscn`：

1. 选中 `VisualRoot`：调整整辆车的整体位置、缩放和旋转。
2. 选中 `VisualRoot/Body`：只调整车体精灵。
3. 选中 `CollisionShape2D`：调整逻辑碰撞范围。
4. 选中 `DamageSmokeAnchor`：调整重度破损烟雾生成位置。
5. 选中 `CargoBarAnchor`：调整黄色矿石载荷条的位置。
6. 保存场景。之后游戏中产生的所有采矿车都会使用该场景。

坦克额外包含 `VisualRoot/Turret`，可以单独移动和缩放炮塔。防御塔和碉堡包含 `VisualRoot/Weapon`。

## 与 Unity Prefab 的对应关系

- Godot `.tscn` / `PackedScene`：对应 Unity Prefab。
- Godot `.tres` / `Resource`：对应 Unity ScriptableObject，只保存数据，不是可视化节点树。
- `VisualRoot`：对应用于整体视觉偏移的父 Transform。
- `Body`、`Turret`、`Weapon`：对应 SpriteRenderer/Animator 子对象。
- `Marker2D`：对应空 GameObject 挂点。

## 动画资源

单位动画已经拆到 `resources/sprite_frames/*.tres`。选择 `AnimatedSprite2D` 后，可以在底部动画面板查看 `stand_0`、`move_0`、`attack_0`、`death_0` 等动画。采矿车额外有 `harvest_0` 和破损动画。

## 旧 `.tres` 配置

`resources/visual_profiles/*.tres` 仍保留为旧工程兼容和动态回退数据，但真实 `.tscn` 场景存在时，位置、缩放、碰撞体和挂点以场景节点为准。不要再使用旧版 `visual_profile_preview.gd` 调整实体。

## 运行时机制

`rts_match.gd` 现在根据实体 ID 加载并实例化对应 `PackedScene`。`unit.gd` 和 `building.gd` 只绑定场景中已有的节点，不会覆盖编辑器保存的 Transform；只有缺少预制场景时才会回退到旧的动态创建逻辑。
