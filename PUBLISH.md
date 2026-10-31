# 发布到 GitHub

这个目录已经是一个可直接上传的仓库根目录。两种发布方式，任选一种。

## 方式 A：网页上传（不需要装 git）

1. 在浏览器打开 <https://github.com/new>
2. 仓库名填 `FarFarWestCheatMod`，描述可写
   `Far Far West cheat mod for UE4SS (UE 5.8, Chinese UI)`，选 Public 或 Private
3. **不要**勾选 "Add a README file"（本目录已有），直接 Create repository
4. 在新仓库页面点 **uploading an existing file**
5. 把本目录里的这些**全部拖进去**：
   ```
   README.md
   CHANGELOG.md
   LICENSE
   .gitignore
   install.ps1
   Mods/            (整个文件夹)
   ue4ss-config/    (整个文件夹)
   FFW_Probe/       (整个文件夹，可选的开发工具)
   ```
6. 底部 Commit changes
7. 想发 Release：仓库右侧 **Releases → Create a new release**，
   tag 填 `v1.0`，把 `release/FarFarWestCheatMod-v1.0.zip` 拖到附件区，发布

> GitHub 网页上传支持拖拽整个文件夹，但 `.gitignore`（点开头的文件）在部分浏览器里拖不进去，
> 可以先用记事本把内容粘进 "create new file" 里手动建。

## 方式 B：装了 git 之后（推荐，便于后续更新）

```powershell
cd <这个目录>
git init
git add .
git commit -m "Far Far West cheat mod v1.0"
git branch -M main
git remote add origin https://github.com/<你的用户名>/FarFarWestCheatMod.git
git push -u origin main
```

之后每次更新只需要：

```powershell
git add .
git commit -m "更新说明"
git push
```

## 发布前检查

- [ ] `Mods/FFW_Cheat/Scripts/main.lua` 里有 `CONFIG` 段，想改数值改那里
- [ ] `README.md` 里的安装步骤和你仓库的实际结构一致
- [ ] `release/` 里的 zip 是最新打的（重新打包：
      `Compress-Archive -Path Mods,ue4ss-config,install.ps1,README.md,LICENSE,CHANGELOG.md -DestinationPath release\FarFarWestCheatMod-v1.0.zip`）
- [ ] 没有把 `UE4SS.log`、`crash_*.dmp` 之类的本地文件传上去（`.gitignore` 已排除）
