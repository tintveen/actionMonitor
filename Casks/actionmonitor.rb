cask "actionmonitor" do
  version "0.1.0"
  sha256 "5d68ed6efc99165c9352094931137e2842c224208d16a3e64e6a5de48a16f562"

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
