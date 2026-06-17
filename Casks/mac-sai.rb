cask "mac-sai" do
  version "1.11.7"
  # Set to the published DMG's hash at release time. build-dmg.sh prints
  # "SHA256:" at the end; the release workflow fills this in automatically.
  sha256 "e91ad9ef5cbd08c17e14fadbef9e9d3ca952855c987c74e108c3d8bb9c66ae0a"

  url "https://github.com/499403698/MacSai/releases/download/v#{version}/MacSai-#{version}.dmg",
      verified: "github.com/499403698/MacSai/"
  name "Mac Sai"
  desc "开源 Mac 清理、优化与恶意软件扫描工具"
  homepage "https://github.com/499403698/MacSai"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Symbol form means "this release or newer"; the old comparison-string
  # form (">= :sonoma") is deprecated by Homebrew and warns on every install.
  depends_on macos: :sonoma

  app "Mac Sai.app"

  zap trash: [
    "~/Library/Application Support/MacClean",
    "~/Library/Caches/com.macclean.app",
    "~/Library/Logs/MacClean",
    "~/Library/Preferences/com.macclean.app.plist",
    "~/Library/Saved Application State/com.macclean.app.savedState",
  ]

  caveats <<~EOS
    部分功能（邮件、Safari、隐私扫描）需要授予完全磁盘访问权限：
      系统设置 → 隐私与安全性 → 完全磁盘访问权限
  EOS
end
