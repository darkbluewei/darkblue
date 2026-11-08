# 超级右键（SuperRightClick）

免费的 macOS Finder 右键增强：菜单直接出现在右键一级。

## 菜单结构
**一级**：剪切 · 粘贴 · 在此处打开终端 · 截屏工具
**二级「新建文件」**：txt / md / docx / xlsx / pptx / py / html / json / 文件夹
**二级「复制路径」**：复制文件路径 / 复制文件名 / 复制文件夹路径
**二级「文件操作」**：移动到… / 复制到… / 批量重命名… / 压缩为 zip / 显示·隐藏隐藏文件

## 云端编译（不用装 Xcode）
1. 注册 GitHub，新建一个仓库（Public 免费额度最多）。
2. 把本文件夹里的**所有文件**上传到仓库，注意要包含 `.github/workflows/build.yml`。
   （网页上传若漏了 `.github`：Add file → Create new file，文件名输入 `.github/workflows/build.yml`，把内容粘进去。）
3. 仓库页面 → Actions → "Build macOS app" → Run workflow，等几分钟。
4. 进入这次运行记录，在底部 Artifacts 下载 `SuperRightClick`，解压得到 `SuperRightClick.zip`，再解压得到 `SuperRightClick.app`。

## 安装
1. 把 `SuperRightClick.app` 拖进「应用程序」。
2. 终端执行（去掉下载隔离标记，否则会提示"已损坏"）：
   ```
   xattr -cr /Applications/SuperRightClick.app
   ```
3. 打开一次 app，点「启用 Finder 扩展」。
4. 没出现菜单：系统设置 → 通用 → 登录项与扩展 → 扩展 → Finder，勾选「超级右键」。然后终端执行 `killall Finder`。

## 说明
- 扩展在沙盒里，只负责显示菜单，真正的文件操作由主程序（后台运行）完成。
- 剪切 = 把文件记下来，粘贴时移动；也可以配合 Finder 的 ⌘C，粘贴时就是复制。
- 首次操作桌面/文稿等位置，系统会弹出权限询问，点允许。
- 无开发者签名（ad-hoc），系统更新后偶尔需要重新启用扩展。
