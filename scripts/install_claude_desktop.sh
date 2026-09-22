#!/usr/bin/env bash
#
# install_claude_desktop.sh
#
# Instaluje Claude Desktop na Linuksie.
#
# Anthropic nie publikuje oficjalnej dystrybucji Claude Desktop dla Linuksa
# w postaci gotowego instalatora dla użytkownika końcowego. Ten skrypt
# korzysta z projektu społecznościowego aaddrick/claude-desktop-debian
# (https://github.com/aaddrick/claude-desktop-debian), który:
#   - pobiera oficjalny pakiet .deb Anthropica z ich repozytorium APT
#     (downloads.claude.ai/claude-desktop/apt/stable) i weryfikuje go
#     sumą SHA256,
#   - opcjonalnie nakłada drobne, jawnie udokumentowane poprawki (patch),
#   - przepakowuje całość do formatu .deb, .rpm lub AppImage,
#     odpowiedniego dla Twojej dystrybucji.
#
# To NIE jest oficjalny produkt Anthropic — to narzędzie tworzone i
# utrzymywane przez społeczność. Skrypt klonuje repozytorium z GitHuba
# i uruchamia jego build.sh, więc uruchamiasz kod strony trzeciej.
#
# Wspierane dystrybucje: Debian/Ubuntu (.deb), Fedora/RHEL (.rpm),
# pozostałe (Arch itp.) -> AppImage. NixOS wymaga ręcznego użycia flake'a
# (patrz komunikat w skrypcie).
#
# Użycie:
#   chmod +x install_claude_desktop.sh
#   ./install_claude_desktop.sh
#
# Skrypt NIE powinien być uruchamiany jako root — sam poprosi o sudo tam,
# gdzie jest to potrzebne.

set -euo pipefail

REPO_URL="https://github.com/aaddrick/claude-desktop-debian.git"

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

warn "Ten skrypt instaluje Claude Desktop na Linuksie za pomocą NIEOFICJALNEGO"
warn "projektu społecznościowego aaddrick/claude-desktop-debian (${REPO_URL})."
warn "Pobiera on jednak oficjalny pakiet Anthropica i weryfikuje go sumą SHA256."

# --- Wykrycie dystrybucji ------------------------------------------------
if [[ ! -f /etc/os-release ]]; then
  err "Nie można wykryć dystrybucji (brak /etc/os-release)."
  exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
DISTRO_ID="${ID:-}"
DISTRO_LIKE="${ID_LIKE:-}"

if [[ "${DISTRO_ID}" == "nixos" ]]; then
  err "NixOS nie jest obsługiwane przez ten skrypt (AppImage zwykle nie działa"
  err "bez dodatkowych zabiegów, a build.sh --build nix wymaga ręcznego --deb)."
  err "Zbuduj bezpośrednio z repo: git clone ${REPO_URL} && cd claude-desktop-debian"
  err "  nix build .#claude-desktop        # lub"
  err "  nix build .#claude-desktop-fhs"
  exit 1
fi

BUILD_FORMAT=""

install_debian_based() {
  log "Wykryto system z rodziny Debian/Ubuntu (ID=${DISTRO_ID})."
  BUILD_FORMAT="deb"
  log "Instalacja zależności (wget, binutils, tar, xz-utils, zstd, dpkg-dev, git)..."
  sudo apt-get update -y
  sudo apt-get install -y wget binutils tar xz-utils zstd dpkg-dev git
}

install_fedora_based() {
  log "Wykryto system Fedora/RHEL (ID=${DISTRO_ID})."
  BUILD_FORMAT="rpm"
  log "Instalacja zależności (wget, binutils, tar, xz, zstd, rpm-build, git)..."
  sudo dnf install -y wget binutils tar xz zstd rpm-build git
}

install_arch_based() {
  log "Wykryto system z rodziny Arch (ID=${DISTRO_ID})."
  BUILD_FORMAT="appimage"
  log "Instalacja zależności (wget, binutils, tar, xz, zstd, git)..."
  sudo pacman -Sy --needed --noconfirm wget binutils tar xz zstd git
}

install_generic_fallback() {
  warn "Dystrybucja '${DISTRO_ID}' nie jest oficjalnie wspierana przez ten skrypt."
  BUILD_FORMAT="appimage"
  if command -v apt-get >/dev/null 2>&1; then
    log "Wykryto apt-get — próbuję zainstalować zależności."
    sudo apt-get update -y
    sudo apt-get install -y wget binutils tar xz-utils zstd git
  elif command -v dnf >/dev/null 2>&1; then
    log "Wykryto dnf — próbuję zainstalować zależności."
    sudo dnf install -y wget binutils tar xz zstd git
  elif command -v pacman >/dev/null 2>&1; then
    log "Wykryto pacman — próbuję zainstalować zależności."
    sudo pacman -Sy --needed --noconfirm wget binutils tar xz zstd git
  elif command -v zypper >/dev/null 2>&1; then
    log "Wykryto zypper — próbuję zainstalować zależności."
    sudo zypper install -y wget binutils tar xz zstd git
  else
    warn "Nie znaleziono znanego menedżera pakietów. Zainstaluj ręcznie:"
    warn "  wget, ar (binutils), tar, xz, zstd, git"
    warn "build.sh z projektu również umie zaproponować instalację brakujących pakietów."
  fi
}

case "${DISTRO_ID}" in
  ubuntu|debian|linuxmint|pop)
    install_debian_based
    ;;
  fedora|rhel|centos|rocky|almalinux)
    install_fedora_based
    ;;
  arch|manjaro|endeavouros)
    install_arch_based
    ;;
  *)
    if [[ "${DISTRO_LIKE}" == *debian* ]]; then
      warn "Dystrybucja '${DISTRO_ID}' bazuje na Debianie — traktuję jak Ubuntu."
      DISTRO_ID="ubuntu"
      install_debian_based
    elif [[ "${DISTRO_LIKE}" == *fedora* || "${DISTRO_LIKE}" == *"rhel"* ]]; then
      warn "Dystrybucja '${DISTRO_ID}' bazuje na Fedorze/RHEL — traktuję jak Fedorę."
      install_fedora_based
    elif [[ "${DISTRO_LIKE}" == *arch* ]]; then
      install_arch_based
    else
      install_generic_fallback
    fi
    ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

log "Klonowanie ${REPO_URL}..."
git clone --depth 1 "${REPO_URL}" "${TMP_DIR}/claude-desktop-debian"
cd "${TMP_DIR}/claude-desktop-debian"

log "Budowanie pakietu (format: ${BUILD_FORMAT})..."
chmod +x ./build.sh
./build.sh --build "${BUILD_FORMAT}"

PACKAGE_FILE="$(find . -maxdepth 4 -iname "claude-desktop-unofficial*.${BUILD_FORMAT}" -print -quit)"
if [[ -z "${PACKAGE_FILE}" ]]; then
  err "Nie znaleziono zbudowanego pakietu (*.${BUILD_FORMAT}) w repozytorium."
  exit 1
fi
ok "Zbudowano pakiet: ${PACKAGE_FILE}"

case "${BUILD_FORMAT}" in
  deb)
    log "Instalacja pakietu .deb..."
    sudo apt-get install -y "${PACKAGE_FILE}" || {
      warn "Instalacja nie powiodła się od razu, próbuję naprawić zależności..."
      sudo dpkg -i "${PACKAGE_FILE}" || true
      sudo apt-get --fix-broken install -y
    }
    ;;
  rpm)
    log "Instalacja pakietu .rpm..."
    sudo dnf install -y "${PACKAGE_FILE}"
    ;;
  appimage)
    APP_DIR="${HOME}/Applications"
    mkdir -p "${APP_DIR}"
    APP_TARGET="${APP_DIR}/$(basename "${PACKAGE_FILE}")"
    log "Kopiowanie AppImage do ${APP_TARGET}..."
    cp "${PACKAGE_FILE}" "${APP_TARGET}"
    chmod +x "${APP_TARGET}"

    DESKTOP_DIR="${HOME}/.local/share/applications"
    mkdir -p "${DESKTOP_DIR}"
    DESKTOP_FILE="${DESKTOP_DIR}/claude-desktop-unofficial.desktop"
    cat > "${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=Claude Desktop (Unofficial)
Comment=Nieoficjalna paczka AppImage Claude Desktop dla Linuksa
Exec=${APP_TARGET}
Terminal=false
Categories=Utility;
EOF
    command -v update-desktop-database >/dev/null 2>&1 && \
      update-desktop-database "${DESKTOP_DIR}" >/dev/null 2>&1 || true

    if ! ldconfig -p 2>/dev/null | grep -q libfuse.so.2; then
      warn "Brak libfuse2 — AppImage może nie wystartować na nowszych dystrybucjach."
      warn "Zainstaluj pakiet libfuse2 (Ubuntu/Debian) lub fuse (inne) ręcznie."
    fi
    ;;
esac

ok "Claude Desktop (nieoficjalna paczka) został zainstalowany."
echo
case "${BUILD_FORMAT}" in
  appimage)
    echo "Uruchom aplikację z menu ('Claude Desktop (Unofficial)') albo bezpośrednio:"
    echo "  ${APP_TARGET}"
    ;;
  *)
    echo "Uruchom aplikację z menu systemu lub poleceniem: claude-desktop"
    ;;
esac
