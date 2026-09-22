#!/usr/bin/env bash
#
# install_docker_desktop.sh
#
# Instaluje Docker Desktop na Linuksie (Ubuntu/Debian lub Fedora).
# Wspierane architektury: amd64/x86_64, arm64/aarch64.
#
# Wymagania Docker Desktop for Linux:
#   - 64-bitowe jądro z obsługą KVM
#   - systemd
#   - AppArmor (Ubuntu/Debian) lub SELinux (Fedora)
#   - cgroup v2
#
# Użycie:
#   chmod +x install_docker_desktop.sh
#   ./install_docker_desktop.sh
#
# Skrypt NIE powinien być uruchamiany jako root — sam poprosi o sudo tam,
# gdzie jest to potrzebne.

set -euo pipefail

log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; }

if [[ "${EUID}" -eq 0 ]]; then
  err "Nie uruchamiaj tego skryptu jako root/sudo. Uruchom jako zwykły użytkownik — sudo zostanie użyte tam, gdzie potrzeba."
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  err "Wymagane jest polecenie 'sudo', a nie zostało znalezione."
  exit 1
fi

# --- Sprawdzenie wirtualizacji (KVM) -----------------------------------
if [[ -e /dev/kvm ]]; then
  ok "Obsługa KVM wykryta (/dev/kvm)."
else
  warn "Nie wykryto /dev/kvm. Docker Desktop wymaga wirtualizacji sprzętowej (KVM)."
  warn "Sprawdź w BIOS/UEFI, czy VT-x/AMD-V jest włączone, oraz czy moduły kvm/kvm_intel|kvm_amd są załadowane."
fi

# --- Wykrycie dystrybucji i architektury --------------------------------
if [[ ! -f /etc/os-release ]]; then
  err "Nie można wykryć dystrybucji (brak /etc/os-release)."
  exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
DISTRO_ID="${ID:-}"
DISTRO_LIKE="${ID_LIKE:-}"

ARCH_RAW="$(uname -m)"
case "${ARCH_RAW}" in
  x86_64) DEB_ARCH="amd64"; RPM_ARCH="x86_64" ;;
  aarch64|arm64) DEB_ARCH="arm64"; RPM_ARCH="aarch64" ;;
  *)
    err "Nieobsługiwana architektura: ${ARCH_RAW}"
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

install_debian_based() {
  log "Wykryto system z rodziny Debian/Ubuntu (ID=${DISTRO_ID})."

  log "Aktualizacja listy pakietów..."
  sudo apt-get update -y

  log "Instalacja zależności (curl, gnupg, ca-certificates, uidmap, qemu)..."
  sudo apt-get install -y \
    ca-certificates curl gnupg \
    uidmap \
    qemu-system-x86 2>/dev/null || sudo apt-get install -y ca-certificates curl gnupg uidmap

  log "Konfiguracja oficjalnego repozytorium Dockera..."
  sudo install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  CODENAME="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || true)}"
  echo \
    "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO_ID} ${CODENAME} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt-get update -y

  DEB_URL="https://desktop.docker.com/linux/main/${DEB_ARCH}/docker-desktop-${DEB_ARCH}.deb"
  DEB_FILE="${TMP_DIR}/docker-desktop-${DEB_ARCH}.deb"

  log "Pobieranie Docker Desktop (${DEB_URL})..."
  curl -fL --progress-bar -o "${DEB_FILE}" "${DEB_URL}"

  log "Instalacja pakietu .deb wraz z zależnościami..."
  sudo apt-get install -y "${DEB_FILE}"
}

install_fedora_based() {
  log "Wykryto system Fedora."

  log "Instalacja wtyczki dnf-plugins-core..."
  sudo dnf -y install dnf-plugins-core

  log "Konfiguracja oficjalnego repozytorium Dockera..."
  sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

  RPM_URL="https://desktop.docker.com/linux/main/${RPM_ARCH}/docker-desktop-${RPM_ARCH}.rpm"
  RPM_FILE="${TMP_DIR}/docker-desktop-${RPM_ARCH}.rpm"

  log "Pobieranie Docker Desktop (${RPM_URL})..."
  curl -fL --progress-bar -o "${RPM_FILE}" "${RPM_URL}"

  log "Instalacja pakietu .rpm wraz z zależnościami..."
  sudo dnf install -y "${RPM_FILE}"
}

case "${DISTRO_ID}" in
  ubuntu|debian)
    install_debian_based
    ;;
  fedora)
    install_fedora_based
    ;;
  *)
    if [[ "${DISTRO_LIKE}" == *debian* ]]; then
      warn "Dystrybucja '${DISTRO_ID}' nie jest oficjalnie wspierana, ale bazuje na Debianie — próbuję jako Ubuntu."
      DISTRO_ID="ubuntu"
      install_debian_based
    else
      err "Nieobsługiwana dystrybucja: ${DISTRO_ID}. Oficjalnie wspierane: Ubuntu, Debian, Fedora."
      exit 1
    fi
    ;;
esac

# --- Grupa docker dla bieżącego użytkownika -----------------------------
if ! getent group docker >/dev/null 2>&1; then
  sudo groupadd docker
fi
if ! id -nG "${USER}" | grep -qw docker; then
  log "Dodawanie użytkownika '${USER}' do grupy 'docker'..."
  sudo usermod -aG docker "${USER}"
  NEED_RELOGIN=1
else
  NEED_RELOGIN=0
fi

ok "Docker Desktop został zainstalowany."
echo
if [[ "${NEED_RELOGIN}" -eq 1 ]]; then
  warn "Wyloguj się i zaloguj ponownie (lub zrestartuj system), aby zmiana grupy 'docker' zaczęła obowiązywać."
fi
echo "Uruchom Docker Desktop poleceniem: systemctl --user start docker-desktop"
echo "albo z menu aplikacji systemu."
