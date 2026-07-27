# 实体视觉调整说明（v0.9.1）

旧版通过 `resources/visual_profiles/*.tres` 和 `visual_profile_preview.tscn` 间接调整位置、缩放的方式已经停用。

现在请直接编辑真实预制场景：

- 单位：`scenes/entities/units/*.tscn`
- 建筑：`scenes/entities/buildings/*.tscn`
- 总览：`scenes/tools/prefab_gallery.tscn`

完整操作见 [`PREFAB_WORKFLOW.md`](PREFAB_WORKFLOW.md)。

## 常用节点

- `VisualRoot`：整体移动、缩放、旋转。
- `Body`：主体精灵。
- `Turret` / `Weapon`：独立炮塔或武器模块。
- `CollisionShape2D`：碰撞体。
- `DamageSmokeAnchor`：受损烟雾挂点。
- `CargoBarAnchor`：采矿车载荷条挂点。
- `ServiceAnchor`：建筑生产出口或维修入口。

保存 `.tscn` 后，运行时新生成的所有对应实体都会采用该场景中的 Transform。

`resources/visual_profiles/*.tres` 只保留作旧数据兼容和缺失预制场景时的回退参数，不再是主要编辑入口。
