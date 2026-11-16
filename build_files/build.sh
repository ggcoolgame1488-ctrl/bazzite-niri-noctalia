
#!/usr/bin/env bash
set -Eeuo pipefail

# Copy custom system files.
cp -avf "/ctx/system_files"/. /

# ============================================================
# 1. Install Niri from stable Dux Labs COPR
# ============================================================

dnf5 install -y dnf5-plugins

dnf5 -y copr enable duxlabs/dux-repo

dnf5 install -y \
    niri \
    xwayland-satellite

# Disable COPR after installation.
dnf5 -y copr disable duxlabs/dux-repo

# ============================================================
# 2. Install Noctalia Shell v5 and desktop utilities
# ============================================================

dnf5 install -y \
    noctalia \
    alacritty \
    fuzzel \
    swaylock \
    brightnessctl \
    wl-clipboard \
    playerctl \
    curl \
    polkit \
    mate-polkit \
    gnome-keyring \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk \
    xdg-desktop-portal-gnome

# ============================================================
# 3. Install greetd and Noctalia Greeter
# ============================================================

dnf5 install -y greetd

dnf5 install -y \
    --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release

dnf5 install -y noctalia-greeter

# Create greeter user if package did not create it.
if ! getent passwd greeter >/dev/null 2>&1; then
    useradd --system \
        --create-home \
        --home-dir /var/lib/noctalia-greeter \
        --shell /sbin/nologin \
        greeter
fi

# Configure greeter state directory.
install -d -m 0755 /etc/tmpfiles.d

printf '%s\n' \
    'd /var/lib/noctalia-greeter 0750 greeter greeter -' \
    > /etc/tmpfiles.d/noctalia-greeter.conf

# Configure greetd.
GREETER_SESSION="$(command -v noctalia-greeter-session)"

install -d -m 0755 /etc/greetd

cat > /etc/greetd/config.toml <<EOF
[default_session]
command = "$GREETER_SESSION"
user = "greeter"
EOF

# Initialize Noctalia Greeter state.
systemd-tmpfiles --create /etc/tmpfiles.d/noctalia-greeter.conf

noctalia-greeter-apply-appearance --setup-system

# ============================================================
# 4. Install default Niri configuration
# ============================================================

NIRI_CONFIG="/etc/skel/.config/niri/config.kdl"

install -d -m 0755 /etc/skel/.config/niri

curl -fsSL \
    https://raw.githubusercontent.com/niri-wm/niri/v26.04/resources/default-config.kdl \
    -o "$NIRI_CONFIG"

# Remove Waybar autostart.
sed -i '/spawn-at-startup "waybar"/d' "$NIRI_CONFIG"

# Start Noctalia automatically.
if ! grep -qF 'spawn-at-startup "noctalia"' "$NIRI_CONFIG"; then
    printf '\nspawn-at-startup "noctalia"\n' >> "$NIRI_CONFIG"
fi

# Start MATE Polkit authentication agent.
if [[ -x /usr/libexec/polkit-mate-authentication-agent-1 ]]; then
    printf '%s\n' \
        'spawn-at-startup "/usr/libexec/polkit-mate-authentication-agent-1"' \
        >> "$NIRI_CONFIG"
fi

# ============================================================
# 5. Configure XDG portals for Niri
# ============================================================

install -d -m 0755 /etc/xdg/xdg-desktop-portal

cat > /etc/xdg/xdg-desktop-portal/niri-portals.conf <<'EOF'
[preferred]
default=gnome;gtk;
org.freedesktop.impl.portal.FileChooser=gtk;
org.freedesktop.impl.portal.Access=gtk;
org.freedesktop.impl.portal.Notification=gtk;
org.freedesktop.impl.portal.Secret=gnome-keyring;
EOF

# ============================================================
# 6. Remove KDE Plasma and GNOME desktop components
# ============================================================

# Disable old display managers.
for unit in \
    sddm.service \
    plasma-login-manager.service \
    gdm.service
do
    systemctl disable "$unit" 2>/dev/null || true
done

# Find installed desktop environment packages.
mapfile -t de_packages < <(
    rpm -qa --qf '%{NAME}\n' |
    grep -E \
    '^(plasma($|-)|kwin($|-)|sddm$|plasma-login-manager$|gnome-shell($|-)|gnome-session($|-)|gdm$|gnome-control-center$|gnome-settings-daemon$|xdg-desktop-portal-kde$)' \
    || true
)

# Remove those packages.
if ((${#de_packages[@]})); then
    dnf5 remove -y "${de_packages[@]}"
fi

# ============================================================
# 7. Enable Noctalia Greeter
# ============================================================

systemctl enable greetd.service
