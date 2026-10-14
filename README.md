# MyAI Office

MyAI Office 是一个统一入口的桌面办公套件，当前把四个原生模块放进同一个 macOS `.app`：

- **MyAI Word**：文字处理，负责 DOCX / DOC / RTF 等文档。
- **MyAI Excel**：电子表格，负责 XLSX / XLS / CSV 等表格。
- **MyAI Power Point**：演示文稿，负责 PPTX 等演示文件。
- **MyAI PDF**：内置 PDF 工作台，用于打开、阅读、整理、合并、拆分和保护 PDF。

启动 `MyAI Office.app` 后，可以从首页新开模块，也可以用“打开文件…”按扩展名自动路由。

## PDF 设计

MyAI PDF 使用 PdfCraft 作为套件内的 PDF 工作台。三个编辑器各自保留它们对 DOCX、XLSX、PPTX 的原生排版与 PDF 导出路径；导出得到 PDF 后，可以直接在 MyAI PDF 里继续阅读、整理、合并或保护。

这是当前开源代码的真实边界：PdfCraft 的公开工程是 PDF 读写与编辑引擎，并不是 DOCX/XLSX/PPTX 的排版转换引擎，因此不能把 Office 文档直接交给 PdfCraft 后声称已经拥有正确的 Office 排版。

## 构建

先在 `ThirdParty/wordcraft`、`ThirdParty/gridcraft`、`ThirdParty/deckcraft`、`ThirdParty/pdfcraft` 中分别完成 Release 构建，再运行：

```sh
./build-suite.sh
./package-dmg.sh
```

## 自动升级与发版

应用启动后会读取 `Info.plist` 中的 `MyAIUpdateManifestURL`，从 GitHub 获取 `updates/latest.json`。如果发现新版本，会先匹配当前版本对应的增量包；没有匹配项时使用完整 ZIP。下载后会校验 SHA-256，内置升级助手会替换应用并自动重启。

版本规则：小修复使用 `patch`，新增大功能使用 `minor`，不兼容变更使用 `major`。例如：

```sh
./release.sh patch
./release.sh minor --notes "新增功能说明"
```

首次发布或无法自动找到上一版本时，用 `--previous-app` 指定上一版 `.app`，即可生成增量包。`--publish` 会把代码推送到 `ddxmu/MyAI-Office`，并把 DMG、完整自动更新 ZIP 和增量 ZIP 上传到对应 GitHub Release；仓库需要公开，否则已安装应用无法免登录读取升级清单。

构建脚本会用 `ThirdParty/craft-fonts` 的开放字体作为可选构建输入，以改善中文、日文等文档的显示与 PDF 嵌入；同时打包对应署名文件。没有使用或打包 LibreOffice。后续 AI 功能会在套件入口和各编辑器中逐步加入。

## 许可证

上游项目的源码按各自仓库中的 MIT / Apache-2.0 条款保留。套件包内的 `Contents/Resources/THIRD-PARTY` 保存了对应许可证和署名说明。ArtCraft 的品牌图像没有复制到 MyAI Office；MyAI Office 使用自己的蓝绿色渐变入口界面。
