# 单位与建筑视觉尺寸可视化校准

Godot 有 Unity Prefab 的对应能力：**场景（PackedScene）+ 可复用资源（Resource）**。本项目的单位和建筑由对局脚本动态生成，因此不能直接在战场场景里拖动每一个运行时实例；v0.9.0 提供了一个编辑器预览场景，把可视化调整写回共享的 `EntityVisualProfile` 资源。

## 推荐工作流：像调整 Prefab 一样拖动

1. 在 Godot 的 FileSystem 中打开 `scenes/tools/visual_profile_preview.tscn`。
2. 选择根节点 `VisualProfilePreview`：
   - `Entity Id` 选择需要预览的单位或建筑。
   - `Profile` 拖入对应的 `resources/visual_profiles/<id>.tres`。
3. 选择子节点 `EditableTransform`。
4. 在 2D 视口中使用移动、缩放工具直接调整：
   - `Position` 对应运行时 `Visual Offset`。
   - `Scale` 对应运行时 `Visual Scale Multiplier`。
5. 再次选择根节点，将 Inspector 中的 **`Save To Profile Trigger`** 勾选一次。
6. 保存场景并重新开始对局。视觉资源会被运行时读取。

黄色十字是单位或建筑的逻辑原点，32px 网格对应默认瓦片尺寸。不要移动根节点；只修改 `EditableTransform`。

## 直接编辑资源

也可以在 `resources/visual_profiles/` 中直接选择 `.tres` 并修改：

- `Visual Scale Multiplier`：只改变图片大小。
- `Visual Offset`：只移动图片，不改变寻路和碰撞。
- `Turret Scale Multiplier`：调整坦克炮塔、防御炮头或碉堡机枪模块。
- `Turret Offset`：移动独立炮塔挂点。
- `Selection Scale`：调整单位点击和框选区域。

## 与 Unity Prefab 的对应关系

| Unity | Godot 本项目 |
|---|---|
| Prefab | `.tscn` 场景 / `PackedScene` |
| ScriptableObject | `.tres` Resource |
| Prefab Variant 参数 | `resources/visual_profiles/*.tres` |
| Scene View 调整 Transform | `visual_profile_preview.tscn` 的 `EditableTransform` |

## 不要这样改

不要直接缩放 `CharacterBody2D`、建筑根节点或碰撞节点。根节点缩放会把碰撞、选择范围和路径逻辑一起改变，重新引入单位拥堵、框选偏差和采矿车卡死。视觉尺寸与逻辑碰撞必须分离。
