# deployBar

`deployBar` ist eine macOS-Menüleisten-App zum Überwachen von GitHub-Deployments. Damit sie auch in einer Linux-/Cloud-Umgebung ordentlich testbar ist, enthält das Paket jetzt zusätzlich einen kleinen CLI-Testmodus.

## Lokal in der Cloud testen

### 1. Unit-Tests ausführen

```bash
swift test
```

### 2. Smoke-Test mit Demo-Daten

```bash
swift run deployBar --demo
```

Der Demo-Modus verwendet deterministische Beispiel-Deployments und braucht weder Keychain noch GitHub-Zugang.

### 3. Live gegen GitHub testen

```bash
GITHUB_TOKEN=ghp_xxx swift run deployBar --live
```

Auf Nicht-macOS-Plattformen liest `deployBar` den Token dafür aus `GITHUB_TOKEN`. Auf macOS bleibt die normale Keychain-Integration der Menüleisten-App unverändert.

## Lokal auf macOS installieren

Ohne Xcode kannst du `deployBar` als normale App nach `~/Applications` installieren:

```bash
./scripts/install-local.sh
```

Danach kannst du die App per Spotlight, Finder, `deploybar` im Terminal oder über die macOS-Login-Items starten. Wenn du eine neue Version aus dem Repo bauen willst, führe das Skript einfach erneut aus.

Zum Entfernen der lokalen Installation:

```bash
./scripts/uninstall-local.sh
```

Das entfernt sowohl `~/Applications/DeployBar.app` als auch den Terminal-Shortcut unter `/opt/homebrew/bin/deploybar`.

## Plattformverhalten

- **macOS:** startet wie bisher die SwiftUI-Menüleisten-App.
- **Linux/Cloud:** startet einen textbasierten Test-Runner, damit Netzwerk-, Parsing- und Statuslogik ohne AppKit geprüft werden können.
