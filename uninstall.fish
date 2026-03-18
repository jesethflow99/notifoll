#!/usr/bin/env fish
# uninstall.fish - Script de desinstalación

set -l RED (set_color red)
set -l GREEN (set_color green)
set -l YELLOW (set_color yellow)
set -l NORMAL (set_color normal)
set -g PKG_MANAGER ""

function detect_package_manager
    if command -v pacman > /dev/null
        set -g PKG_MANAGER pacman
    else if command -v apt-get > /dev/null
        set -g PKG_MANAGER apt
    else if command -v dnf > /dev/null
        set -g PKG_MANAGER dnf
    else if command -v yum > /dev/null
        set -g PKG_MANAGER yum
    else if command -v zypper > /dev/null
        set -g PKG_MANAGER zypper
    else if command -v apk > /dev/null
        set -g PKG_MANAGER apk
    else if command -v xbps-remove > /dev/null
        set -g PKG_MANAGER xbps
    else if command -v emerge > /dev/null
        set -g PKG_MANAGER emerge
    else
        return 1
    end
    return 0
end

function remove_system_dependencies
    if not command -v sudo > /dev/null
        echo $YELLOW"⚠️  'sudo' no disponible. Omitiendo eliminación de dependencias del sistema."$NORMAL
        return 0
    end

    switch $PKG_MANAGER
        case pacman
            sudo pacman -Rns --noconfirm libnotify xclip xdotool xorg-xauth wl-clipboard python-pip
        case apt
            sudo apt-get remove -y libnotify-bin xclip xdotool xauth wl-clipboard python3-pip python3-venv
            sudo apt-get autoremove -y
        case dnf
            sudo dnf remove -y libnotify xclip xdotool xauth wl-clipboard python3-pip python3-virtualenv
        case yum
            sudo yum remove -y libnotify xclip xdotool xauth wl-clipboard python3-pip python3-virtualenv
        case zypper
            sudo zypper --non-interactive remove --clean-deps libnotify-tools xclip xdotool xauth wl-clipboard python3-pip python3-virtualenv
        case apk
            sudo apk del libnotify libnotify-tools xclip xdotool xauth wl-clipboard py3-pip py3-virtualenv
        case xbps
            sudo xbps-remove -Ry libnotify xclip xdotool xauth wl-clipboard python3-pip python3-virtualenv
        case emerge
            sudo emerge --ask=n --depclean x11-libs/libnotify x11-misc/xclip x11-misc/xdotool x11-apps/xauth gui-apps/wl-clipboard dev-python/pip dev-python/virtualenv
        case '*'
            echo $YELLOW"⚠️  Gestor de paquetes no soportado para purga automática"$NORMAL
            return 1
    end
end

echo $RED"🗑️  Desinstalando Notifoll..."$NORMAL

# Verificar que no estamos como root
if test (id -u) -eq 0
    echo $RED"❌ No ejecutes este script como root"$NORMAL
    exit 1
end

# Detener y deshabilitar servicio
echo "🛑 Deteniendo servicio..."
systemctl --user stop notifoll 2>/dev/null
systemctl --user disable notifoll 2>/dev/null

# Eliminar archivos de servicio
echo "📁 Eliminando archivos de servicio..."
rm -vf ~/.config/systemd/user/notifoll.service

# Eliminar binarios
echo "📁 Eliminando binarios..."
if command -v sudo > /dev/null
    sudo rm -vf /usr/local/bin/notifoll
    sudo rm -vf /usr/local/bin/notifoll-service
    sudo rm -vf /usr/local/bin/notifoll-service.py 2>/dev/null
else
    rm -vf /usr/local/bin/notifoll
    rm -vf /usr/local/bin/notifoll-service
    rm -vf /usr/local/bin/notifoll-service.py 2>/dev/null
end

# Eliminar entorno virtual
echo "📁 Eliminando entorno virtual..."
rm -rvf ~/.local/share/notifoll

# Eliminar archivo PID
rm -vf /tmp/notifoll.pid

# Preguntar si eliminar configuración
echo ""
echo $YELLOW"¿Eliminar también la configuración? (s/n)"$NORMAL
read -l delete_config
if contains s S $delete_config
    echo "📁 Eliminando configuración..."
    rm -rvf ~/.config/notifoll
    echo $GREEN"✅ Configuración eliminada"$NORMAL
else
    echo $YELLOW"⚠️  Configuración conservada en ~/.config/notifoll"$NORMAL
end

# Eliminar autocompletado
echo "📁 Eliminando autocompletado..."
rm -vf ~/.config/fish/completions/notifoll.fish

# Eliminar alias si existe
echo "📁 Limpiando alias..."
if test -f ~/.config/fish/config.fish
    # Hacer backup
    cp ~/.config/fish/config.fish ~/.config/fish/config.fish.bak
    # Eliminar líneas con alias nf
    sed -i '/alias nf=/d' ~/.config/fish/config.fish
    echo "✅ Alias eliminado (backup en config.fish.bak)"
end

# Recargar systemd
echo "🔄 Recargando systemd..."
systemctl --user daemon-reload

# Preguntar si eliminar dependencias del sistema
echo ""
echo $YELLOW"¿Eliminar también dependencias del sistema (libnotify/xclip/xdotool/xauth/wl-clipboard/pip/venv)? (s/n)"$NORMAL
echo $YELLOW"⚠️  Esto puede afectar otras aplicaciones que también las usan."$NORMAL
read -l remove_deps
if contains s S $remove_deps
    if detect_package_manager
        echo "📦 Eliminando dependencias usando: $PKG_MANAGER"
        remove_system_dependencies
        echo $GREEN"✅ Purga de dependencias finalizada (si estaban instaladas)"$NORMAL
    else
        echo $YELLOW"⚠️  No se detectó gestor soportado. Elimina dependencias manualmente."$NORMAL
    end
else
    echo $YELLOW"⚠️  Dependencias del sistema conservadas"$NORMAL
end

echo ""
echo $GREEN"✅ Notifoll desinstalado correctamente"$NORMAL
