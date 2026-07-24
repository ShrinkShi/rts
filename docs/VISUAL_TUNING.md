# 单位与建筑视觉尺寸手动校准

v0.8.4 将战场贴图尺寸与逻辑碰撞彻底分离。不要直接缩放运行时的单位根节点，否则会同时影响碰撞、选择和路径行为。

## 在 Godot 编辑器中调整

1. 在 Godot 的 **FileSystem** 面板展开：`resources/visual_profiles/`。
2. 选择需要调整的资源，例如：
   - `tank.tres`：主战坦克。
   - `rifle.tres`：步枪兵。
   - `power.tres`：发电站。
   - `turret.tres`：防御炮塔。
3. 在右侧 **Inspector** 修改字段。
4. 保存资源，重新进入一局对战。当前对局会缓存资源，不建议在单位已生成后热改。

## 字段说明

- `Visual Scale Multiplier`
  - `1,1`：保持默认大小。
  - `1.1,1.1`：整体放大 10%。
  - `0.9,0.9`：整体缩小 10%。
  - 一般保持 X、Y 相同，避免单位变形。
- `Visual Offset`
  - 仅移动图片，不改变逻辑位置。
  - X 正数向右，负数向左。
  - Y 正数向下，负数向上。
- `Turret Scale Multiplier`
  - 仅调整坦克炮塔、防御炮头或碉堡机枪模块。
- `Turret Offset`
  - 只移动独立炮塔挂点。
- `Selection Scale`
  - 调整单位点击和框选区域大小，不改变碰撞。

## 推荐调试顺序

1. 先调整 `Visual Scale Multiplier`。
2. 再用 `Visual Offset.y` 对齐单位脚底或建筑地基。
3. 对带独立炮塔的对象，再调整 `Turret Offset`。
4. 最后调整 `Selection Scale`，保证点击区域与画面基本一致。

## 不要修改的内容

- 不要直接修改 `CharacterBody2D.scale` 或建筑根节点 `scale`。
- 不要为了匹配图片随意扩大 `collision_radius`。
- 视觉尺寸和碰撞尺寸不是同一个概念；碰撞过大会重新引入单位拥堵和采矿车卡死。
