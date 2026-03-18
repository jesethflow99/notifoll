#!/usr/bin/env fish
# fix-x11-complete.fish - Diagnóstico y reparación completa de X11 para servicios

set -l GREEN (set_color green)
set -l RED (set_color red)
set -l YELLOW (set_color yellow)
set -l NORMAL (set_color normal)

echo "🔍 Diagnosticando entorno X11..."

# 1. Obtener información de la sesión actual
echo "📊 Información de la sesión actual:"
echo "   DISPLAY: $DISPLAY"
echo "   XAUTHORITY: $XAUTHORITY"
echo "   DBUS_SESSION_BUS_ADDRESS: $DBUS_SESSION_BUS_ADDRESS"
echo "   XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"

# 2. Obtener el magic cookie actual
set MAGIC_COOKIE (xauth list $DISPLAY 2>/dev/null | head -1 | awk '{print $3}')
if test -z "$MAGIC_COOKIE"
    echo $RED"❌ No se pudo obtener magic cookie"$NORMAL
    # Generar uno nuevo
    xauth generate $DISPLAY . trusted
    set MAGIC_COOKIE (xauth list $DISPLAY | head -1 | awk '{print $3}')
end
echo "✅ Magic cookie obtenido"

# 3. Crear Xauthority para el servicio
mkdir -p ~/.config/notifoll
rm -f ~/.config/notifoll/Xauthority
xauth -f ~/.config/notifoll/Xauthority add $DISPLAY . $MAGIC_COOKIE
chmod 600 ~/.config/notifoll/Xauthority
echo "✅ Xauthority creado: ~/.config/notifoll/Xauthority"

# 4. Actualizar el wrapper (ya debería estar bien)
echo "📝 Verificando wrapper..."

# 5. Actualizar archivo de servicio con las variables correctas
echo "📝 Actualizando archivo de servicio..."
set SERVICE_CONTENT '[Unit]
Description=Notifoll - Ollama Text Processor Service
Documentation=https://github.com/tuusuario/notifoll
After=network.target graphical-session.target ollama.service
Wants=graphical-session.target ollama.service

[Service]
Type=simple
ExecStart=/usr/local/bin/notifoll-service
Restart=on-failure
RestartSec=5
Environment="DISPLAY='"$DISPLAY"'"
Environment="XAUTHORITY=%h/.config/notifoll/Xauthority"
Environment="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus"
Environment="XDG_RUNTIME_DIR=/run/user/%U"
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target'

echo "$SERVICE_CONTENT" > ~/.config/systemd/user/notifoll.service
echo "✅ Archivo de servicio actualizado"

# 6. Recargar y reiniciar
echo "🔄 Recargando systemd..."
systemctl --user daemon-reload
systemctl --user stop notifoll
sleep 1
echo "🚀 Iniciando servicio..."
systemctl --user start notifoll

# 7. Verificar
sleep 3
set -l service_state (systemctl --user is-active notifoll 2>/dev/null)
echo ""
echo "📊 Estado del servicio:"
switch "$service_state"
    case active
        echo $GREEN"✅ Servicio funcionando correctamente"$NORMAL
        echo ""
        echo "Últimos logs:"
        journalctl --user -u notifoll -n 10 --no-pager
    case '*'
        echo $RED"❌ El servicio aún falla"$NORMAL
        echo "Estado: $service_state"
        echo ""
        echo "📋 Últimos logs:"
        journalctl --user -u notifoll -n 20 --no-pager
end

echo ""
echo "🔍 Para más detalles: journalctl --user -u notifoll -f"