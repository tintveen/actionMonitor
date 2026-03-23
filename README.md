# actionMonitor

`actionMonitor` ist eine macOS-Menüleisten-App zum Überwachen von GitHub-Deployments. Damit sie auch in einer Linux-/Cloud-Umgebung ordentlich testbar ist, enthält das Paket jetzt zusätzlich einen kleinen CLI-Testmodus.

## Lokal in der Cloud testen

### 1. Unit-Tests ausführen

```bash
swift test
```

### 2. Smoke-Test mit Demo-Daten

```bash
swift run actionMonitor --demo
```

Der Demo-Modus verwendet deterministische Beispiel-Deployments und braucht weder Keychain noch GitHub-Zugang. Auf macOS startet dabei weiterhin die Menüleisten-App, aber ohne Token-Abfrage und ohne Keychain-Zugriff.

### 3. Live gegen GitHub testen

```bash
GITHUB_TOKEN=ghp_xxx swift run actionMonitor --live
```

Auf Nicht-macOS-Plattformen liest `actionMonitor` den Token dafür aus `GITHUB_TOKEN`. Auf macOS bleibt die normale Keychain-Integration der Menüleisten-App unverändert.

## Lokal auf macOS installieren

Ohne Xcode kannst du `actionMonitor` als normale App nach `~/Applications` installieren:

```bash
./scripts/install-local.sh
```

Danach kannst du die App per Spotlight, Finder, `actionMonitor` im Terminal oder über die macOS-Login-Items starten. Wenn du eine neue Version aus dem Repo bauen willst, führe das Skript einfach erneut aus.

Für dauerhaft gemerkten Keychain-Zugriff ist die installierte App der bessere Startpunkt als `swift run`, weil macOS Berechtigungen zuverlässiger an eine feste App-Installation koppelt als an einen Development-Run aus dem Build-Ordner.

Zum Entfernen der lokalen Installation:

```bash
./scripts/uninstall-local.sh
```

Das entfernt sowohl `~/Applications/actionMonitor.app` als auch den Terminal-Shortcut unter `/opt/homebrew/bin/actionMonitor`.

## Plattformverhalten

- **macOS:** startet wie bisher die SwiftUI-Menüleisten-App.
- **Linux/Cloud:** startet einen textbasierten Test-Runner, damit Netzwerk-, Parsing- und Statuslogik ohne AppKit geprüft werden können.
