# MyAI Office 0.7.5 验收记录

环境：macOS / Apple Silicon，2026-10-16。用户原始业务文件未修改、未上传；WPS 仅用于打开临时只读副本做黑盒显示对照。

## 本次范围

- 修复 MyAI Word 编辑界面中中文 DOCX 的蓝色“双横杠”误报。
- 误报来源是英文 grammar proofing 对中文缩进、中文排版间隔和表格日期尾随空格的 `Extra space` 标记。
- 英文正文中真正的重复空格检查保持不变。

## 对照文件与测试证据

- WPS 对照窗口显示原始 DOCX 没有蓝色双横线；WPS 未被关闭或修改。
- 最终 MyAI Word 通过 `review.issues` 检查该 DOCX，结果为空数组。
- 最终编辑界面截图确认蓝色双横线消失：`/tmp/myai-ctdi-0404-075-final.png`。
- 最终页面渲染仍为 5 页，页面 1 渲染图确认标题、公司名、编写/审核/批准下划线、日期和表格保持可见：`/tmp/myai-ctdi-0404-075-page1.png`。
- `cargo fmt --all -- --check` 通过。
- `cargo test -p wordcraft-proof` 通过：126 项通过；包含中文排版空格和表格尾随空格回归测试，英文重复空格测试仍通过。
- `myai-writer-cli info` 报告文档未加密、未修改、5 页、69 个段落；原始 DOCX 未写回。
- 最终应用通过 `codesign --verify --deep --strict`。
- `QA/verify-update.py --base ../MyAI-Office-0.7.4-arm64.zip --manifest updates/latest.json` 通过：目标哈希/权限/签名、增量重建、损坏包、错误版本、不安全路径和被修改基线检查均通过。

## 发布资产

- 完整自动更新 ZIP：164,089,666 字节。
- DMG：163,878,900 字节。
- 0.7.4 → 0.7.5 bsdiff-v2 增量包：912,736 字节，约 891 KiB。

本版只针对用户提出的中文 DOCX 编辑界面语法误标记进行局部修复，不宣称与 WPS 一比一复刻。
