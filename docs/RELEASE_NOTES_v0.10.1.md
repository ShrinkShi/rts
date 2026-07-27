# v0.10.1 — Godot 4.7.1 解析错误修复

## 修复

- 修复 `ra2_database_browser.gd` 中 `UIFactory.heading()` 与 `UIFactory.muted_label()` 返回类型不明确，导致 Godot 4.7.1 无法推断 `title`、`summary_label` 类型的问题。
- 为 `UIFactory` 的所有公开工厂函数补齐参数类型和返回类型，防止后续 UI 脚本再次出现同类解析错误。
- 将 RA2 数据库浏览器中的国家实体列表显式声明为 `Array[String]`。
- 新增 `tools/validate_gdscript_inference.py`，检查自定义无返回类型函数被 `:=` 推断变量接收的高风险写法。

## 根因

v0.10.0 的静态检查只验证了文件结构、资源路径和数据完整性，没有运行 Godot 的 GDScript 解析器。`:=` 要求右侧表达式具有可确定的静态类型，而旧版 `UIFactory.heading()`/`muted_label()` 没有声明返回类型，因此在 Godot 4.7.1 中触发 Parser Error。
