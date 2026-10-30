# 旅前英语

面向本人和亲友的 iPhone 旅游英语学习应用。开发依据见 [规划文档](docs/README.md)。

## 当前阶段

已开始 G1/G2 技术验证版本：SwiftUI 中文界面、Apple Translation 资源准备与中英双向设备端翻译入口、云端构建流程和待重签 IPA 打包工具。

**还未经过 Xcode 编译、iPhone 安装或飞行模式实测，G1/G2 尚未通过。** 当前没有生成 IPA；课程、录音、评分、AI 对话、后端与月度预算执行器尚未开发。不能把这个验证版当作完整学习应用。

## 文件

- `ios/project.json`：XcodeGen 工程规格，生成 iOS 18+ 真机和模拟器目标。
- `ios/TravelEnglish/`：原生 SwiftUI 验证应用，无在线翻译回退、无密钥。
- `.github/workflows/ios-validation.yml`：手动触发的 macOS 构建，编译模拟器和真机目标，输出日志和待重签 IPA。
- `scripts/package_ipa.py`：校验 arm64 iPhoneOS Mach-O，再打包 Payload 并计算 SHA256，不负责签名。
- `tests/`：IPA 打包工具测试。
- [首次构建与实机验证](docs/06-首次构建与实机验证.md)：当前需要的操作。

## Windows 本地检查

在项目目录运行：

```powershell
python -m unittest discover -s tests -v
python -m json.tool ios/project.json
```

Windows 不能用这些检查替代 iOS 编译。没有引入对话或语音云服务，因此当前验证版本不发出收费模型请求。

## 有 Mac 时

安装 Xcode（选定版本）、Python 3 和 XcodeGen 2.46.0，在项目根目录运行：

```sh
xcodegen generate --spec ios/project.json --project ios
xcodebuild -project ios/TravelEnglish.xcodeproj -scheme TravelEnglish -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ARCHS=arm64 build
python3 scripts/package_ipa.py build/device/Build/Products/Release-iphoneos/TravelEnglish.app build/TravelEnglish-unsigned.ipa
```

未签名 IPA 不能直接点开安装。使用 Windows 工具免费签名后，仍需验证 Translation 能力是否正常。
