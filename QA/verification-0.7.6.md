# MyAI Office 0.7.6 验收记录

环境：macOS / Apple Silicon，2026-10-16。用户原始业务文件未修改；WPS 仅用于打开临时副本做黑盒显示对照，未关闭、未修改 WPS，也未读取 WPS 私有代码或资源。

## 本次范围

- 修复 MyAI Word 默认显示蓝色表格网格线覆盖真实边框的问题。
- 关闭默认的编辑辅助网格线；文档自身的表格边框继续按原始格式绘制。
- 避免辅助线穿过合并单元格，恢复中文业务文档中常见的黑色表格边框和合并结构显示。

## 对照文件与测试证据

- 使用桌面“中电信数智科技-ITSS运行维护3级新版”目录中的 4 份 DOCX 和 1 份老式 DOC 临时副本，分别在 WPS 和 MyAI Word 中打开对照：内部审核检查表、管理评审报告、信息资产风险评估表、上半年服务报告、管理评审表（.doc）。
- WPS 对照显示表格边框为文档自身的黑色边框；修复后的 MyAI Word 截图 `/tmp/myai-itss-0803-risk-fixed.png` 已去除蓝色覆盖线，黑色边框和合并单元格结构可见。
- `cargo fmt --all -- --check` 通过。
- `cargo test -p wordcraft-layout --lib` 通过：242 项通过。
- `page_and_table_gridlines_toggle_independently` 通过，确认页面网格线与表格辅助网格线独立，默认均关闭辅助线而不影响文档边框。
- `cargo test -p wordcraft-engine`：438 项中 437 项通过；唯一失败为仓库原有的文件访问架构约束测试，失败位置 `crates/engine/src/cmd/file.rs:264` 未在本次改动中变更。
- VendorPatches/wordcraft.patch 通过反向应用校验。

## 已知差异

WPS 与 MyAI Word 对部分复杂中文文档仍存在分页数量差异：内部审核检查表为 WPS 24 页、MyAI 26 页；管理评审报告为 WPS 3 页、MyAI 5 页；上半年服务报告为 WPS 10 页、MyAI 12 页。信息资产风险评估表和老式 DOC 的页数目前一致。该项属于后续版式/分页兼容性工作，本版不宣称已经达到 WPS 一比一排版。

本版不使用或集成 LibreOffice，不复制 WPS 的代码、引擎或字库。
