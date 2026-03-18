#!/usr/bin/env fish
# uninstall.fish - Script de desinstalación

set -l RED (set_color red)
set -l GREEN (set_color green)
set -l YELLOW (set_color yellow)
set -l NORMAL (set_color normal)

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

echo ""
echo $GREEN"✅ Notifoll desinstalado correctamente"$NORMAL