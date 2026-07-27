# v0.9.2 Godot 4.7.1 警告清理

本版本针对 Godot 4.7.1 调试器显示的 29 条黄色 GDScript 警告进行清理。

## 修复内容

- EventBus 信号由其他系统通过 Autoload 发射，使用精确的 `unused_signal` 抑制，不关闭全局警告。
- 修复整数除法警告，避免依赖隐式截断。
- 重命名与 `Node2D.position`、`Control.position` 冲突的局部变量和参数。
- 修复 `speaking_unit` 使用前未赋值。
- 移除未使用的 `refinery` 局部变量。
- 将有意未使用的接口参数改为下划线前缀。
- 消除全局类 `EntityVisualProfile` 与预加载常量同名警告。
- 消除 HUD Lambda 参数与下层循环变量重名警告。

这些修复不改变单位、建筑、AI、采矿或预制场景的游戏行为。
