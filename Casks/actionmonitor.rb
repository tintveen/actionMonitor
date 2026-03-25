cask "actionmonitor" do
  version "0.1.0"
  sha256 "33cd1f0befbc8ebc77d6a725d0f01419e9cbdb7dea423192cd1c9f152f3f5074"

  url "https://github.com/tintveen/actionMonitor/releases/download/v0.1.0/actionMonitor-0.1.0-macos.zip"
  name "actionMonitor"
  desc "Menu bar app for monitoring GitHub Actions workflows on macOS"
  homepage "https://github.com/tintveen/actionMonitor"

  depends_on macos: ">= :sonoma"

  app "actionMonitor.app"

  caveats <<~EOS
    actionMonitor is currently distributed as an unsigned app.
    If macOS blocks launch, open System Settings > Privacy & Security and allow the app to run,
    or remove quarantine for the installed app with:
      xattr -d com.apple.quarantine "/Applications/actionMonitor.app"
  EOS
end
