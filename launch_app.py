import subprocess
import sys
import os

def run_command(command, description):
    print(f"\n[FindYouX] {description}...")
    try:
        process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in process.stdout:
            print(line, end="")
        process.wait()
        return process.returncode == 0
    except Exception as e:
        print(f"Fehler: {e}")
        return False

def main():
    print("========================================")
    print("   FindYouX Pro - Auto-Launcher v1.0")
    print("========================================")

    # 1. Check for Flutter
    if not run_command("flutter --version", "Prüfe Flutter-Installation"):
        print("\n[!] FEHLER: 'flutter' Befehl nicht gefunden.")
        print("Bitte stelle sicher, dass das Flutter SDK installiert und im PATH ist.")
        return

    # 2. Check for Devices
    print("\n[FindYouX] Suche nach angeschlossenen Geräten...")
    devices = subprocess.check_output("flutter devices", shell=True, text=True)
    print(devices)

    if "No devices available" in devices:
        print("\n[!] FEHLER: Kein Handy gefunden.")
        print("Bitte verbinde dein Honor Magic 6 Lite über USB oder WLAN-Mirror.")
        return

    # 3. Start Build & Run
    print("\n[?] Welchen Modus möchtest du starten?")
    print("1: Debug (Schnell, mit Log-Infos)")
    print("2: Release (Vollgas, maximale Sicherheit)")

    choice = input("\nWähle 1 oder 2: ").strip()

    if choice == "2":
        cmd = "flutter run --release"
        desc = "Baue und installiere RELEASE Version auf dein Handy"
    else:
        cmd = "flutter run"
        desc = "Baue und installiere DEBUG Version auf dein Handy"

    if run_command(cmd, desc):
        print("\n[✓] ERFOLG: Die App sollte nun auf deinem Honor starten!")
    else:
        print("\n[X] FEHLER beim Starten der App.")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nAbgebrochen.")
    input("\nDrücke ENTER zum Beenden...")
