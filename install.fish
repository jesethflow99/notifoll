#!/usr/bin/env fish
# install.fish - Instalador mejorado para Notifoll

set -l BLUE (set_color blue)
set -l GREEN (set_color green)
set -l RED (set_color red)
set -l YELLOW (set_color yellow)
set -l NORMAL (set_color normal)
set -l SCRIPT_DIR (cd (dirname (status --current-filename)); and pwd)

# Verificar que no estamos ejecutando como root
if test (id -u) -eq 0
    echo $RED"❌ No ejecutes este script como root"$NORMAL
    echo "Ejecútalo como usuario normal (usará sudo cuando sea necesario)"
    exit 1
end

# Verificar sudo
if not command -v sudo > /dev/null; or not sudo -v > /dev/null 2>&1
    echo $RED"❌ Se necesitan permisos de sudo para instalar dependencias del sistema"$NORMAL
    exit 1
end

echo $BLUE"=================================="$NORMAL
echo $GREEN"Instalando Notifoll para Fish Shell"$NORMAL
echo $BLUE"=================================="$NORMAL

# Detectar gestor de paquetes
set -g PKG_MANAGER ""
set -g __NOTIFOLL_APT_UPDATED 0
set -g __NOTIFOLL_XBPS_UPDATED 0

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
    else if command -v xbps-install > /dev/null
        set -g PKG_MANAGER xbps
    else if command -v emerge > /dev/null
        set -g PKG_MANAGER emerge
    else
        return 1
    end
    return 0
end

function install_packages
    set -l packages $argv
    if test (count $packages) -eq 0
        return 0
    end

    switch $PKG_MANAGER
        case pacman
            sudo pacman -S --noconfirm --needed $packages
        case apt
            if test $__NOTIFOLL_APT_UPDATED -eq 0
                sudo apt-get update
                set -g __NOTIFOLL_APT_UPDATED 1
            end
            sudo apt-get install -y $packages
        case dnf
            sudo dnf install -y $packages
        case yum
            sudo yum install -y $packages
        case zypper
            sudo zypper --non-interactive install --no-recommends $packages
        case apk
            sudo apk add $packages
        case xbps
            if test $__NOTIFOLL_XBPS_UPDATED -eq 0
                sudo xbps-install -Suy
                set -g __NOTIFOLL_XBPS_UPDATED 1
            end
            sudo xbps-install -y $packages
        case emerge
            sudo emerge --ask=n $packages
        case '*'
            echo $RED"❌ Gestor de paquetes no soportado automáticamente"$NORMAL
            return 1
    end
end

function run_smoke_test
    set -l failed 0

    if not test -x /usr/local/bin/notifoll-service
        echo $RED"❌ Smoke test: no existe /usr/local/bin/notifoll-service"$NORMAL
        set failed 1
    end

    if not test -f ~/.config/systemd/user/notifoll.service
        echo $RED"❌ Smoke test: no existe ~/.config/systemd/user/notifoll.service"$NORMAL
        set failed 1
    end

    if not ~/.local/share/notifoll/venv/bin/python -c "import pyperclip,pynput,requests,watchdog" > /dev/null 2>&1
        echo $RED"❌ Smoke test: imports Python fallaron en el venv"$NORMAL
        set failed 1
    end

    if not systemctl --user is-active notifoll > /dev/null 2>&1
        echo $RED"❌ Smoke test: servicio notifoll no está activo"$NORMAL
        set failed 1
    end

    if test $failed -eq 0
        return 0
    end
    return 1
end

if not detect_package_manager
    echo $RED"❌ No se detectó un gestor de paquetes compatible"$NORMAL
    echo "Instala manualmente: python3, python3-pip, python3-venv, libnotify, xclip, xdotool, xauth, wl-clipboard"
    exit 1
end
echo "📦 Gestor detectado: $PKG_MANAGER"

# Verificar Python
echo "🔍 Verificando Python..."
if not command -v python3 > /dev/null
    echo $RED"❌ Python3 no está instalado"$NORMAL
    switch $PKG_MANAGER
        case pacman
            install_packages python
        case apt dnf yum zypper xbps apk
            install_packages python3
        case emerge
            install_packages dev-lang/python
    end
    if not command -v python3 > /dev/null
        echo $RED"❌ No se pudo instalar python3 automáticamente"$NORMAL
        exit 1
    end
end

if not python3 -m venv --help > /dev/null 2>&1
    echo $YELLOW"⚠️  Módulo venv no disponible. Instalando soporte venv..."$NORMAL
    switch $PKG_MANAGER
        case pacman
            install_packages python
        case apt
            install_packages python3-venv
        case dnf yum zypper xbps
            install_packages python3-virtualenv
        case apk
            install_packages py3-virtualenv
        case emerge
            install_packages dev-python/virtualenv
    end
    if not python3 -m venv --help > /dev/null 2>&1
        echo $RED"❌ No se pudo habilitar python3-venv automáticamente"$NORMAL
        exit 1
    end
end

set python_version (python3 --version 2>&1)
echo $GREEN"✅ $python_version"$NORMAL

# Verificar pip
if not command -v pip3 > /dev/null
    echo "Instalando pip3..."
    switch $PKG_MANAGER
        case pacman
            install_packages python-pip
        case apt dnf yum zypper xbps
            install_packages python3-pip
        case apk
            install_packages py3-pip
        case emerge
            install_packages dev-python/pip
    end
    if not command -v pip3 > /dev/null
        echo $RED"❌ No se pudo instalar pip3 automáticamente"$NORMAL
        exit 1
    end
end

# Instalar dependencias del sistema
echo "📦 Verificando dependencias del sistema..."
set deps_installed false

if not command -v notify-send > /dev/null
    echo $YELLOW"⚠️  libnotify no instalado. Instalando..."$NORMAL
    switch $PKG_MANAGER
        case pacman dnf yum emerge xbps
            install_packages libnotify
        case apt
            install_packages libnotify-bin
        case zypper
            install_packages libnotify-tools
        case apk
            install_packages libnotify libnotify-tools
    end
    set deps_installed true
end

if not command -v xclip > /dev/null
    echo $YELLOW"⚠️  xclip no instalado. Instalando..."$NORMAL
    install_packages xclip
    set deps_installed true
end

if not command -v xdotool > /dev/null
    echo $YELLOW"⚠️  xdotool no instalado (opcional)..."$NORMAL
    install_packages xdotool
    set deps_installed true
end

if not command -v xauth > /dev/null
    echo $YELLOW"⚠️  xauth no instalado. Instalando..."$NORMAL
    switch $PKG_MANAGER
        case pacman
            install_packages xorg-xauth
        case '*'
            install_packages xauth
    end
    set deps_installed true
end

if not command -v wl-copy > /dev/null
    echo $YELLOW"⚠️  wl-clipboard no instalado (recomendado para Wayland)..."$NORMAL
    switch $PKG_MANAGER
        case emerge
            install_packages gui-apps/wl-clipboard
        case '*'
            install_packages wl-clipboard
    end
    set deps_installed true
end

# Crear directorios necesarios
echo "📁 Creando directorios..."
mkdir -p ~/.config/systemd/user
mkdir -p ~/.config/notifoll
mkdir -p ~/.local/bin
mkdir -p ~/.config/fish/completions
mkdir -p ~/.local/share/notifoll/venv

# Crear entorno virtual
echo "🐍 Creando entorno virtual Python..."
python3 -m venv ~/.local/share/notifoll/venv

# Encontrar la ruta real de site-packages (maneja diferentes versiones de Python)
set -l VENV_SITE_PACKAGES ~/.local/share/notifoll/venv/lib/python*/site-packages
set -l SITE_PACKAGES (echo $VENV_SITE_PACKAGES | tr ' ' '\n' | head -1)  # Toma la primera que exista
if not test -d "$SITE_PACKAGES"
    echo $RED"❌ No se encontró el directorio site-packages"$NORMAL
    exit 1
end
echo "📦 Directorio site-packages: $SITE_PACKAGES"

# Instalar dependencias Python
echo "📦 Instalando dependencias Python..."
~/.local/share/notifoll/venv/bin/pip install --upgrade pip
~/.local/share/notifoll/venv/bin/pip install pyperclip pynput requests watchdog

echo "✅ Dependencias instaladas:"
~/.local/share/notifoll/venv/bin/pip list | grep -E "pyperclip|pynput|requests|watchdog"

# Copiar script Python al site-packages
echo "📦 Copiando notifoll-service.py..."
if test -f "notifoll-service.py"
    cp notifoll-service.py "$SITE_PACKAGES/"
    chmod +x "$SITE_PACKAGES/notifoll-service.py"
    echo "✅ Copiado: notifoll-service.py → $SITE_PACKAGES/"
else
    echo $RED"❌ Error: notifoll-service.py no encontrado"$NORMAL
    exit 1
end

# Crear wrapper script mejorado (usa el python del venv directamente)
echo "📝 Creando wrapper script..."
set WRAPPER_CONTENT '#!/usr/bin/env bash
# Wrapper mejorado para notifoll

USER_HOME="${HOME}"
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(eval echo ~$SUDO_USER)
fi

VENV_PYTHON="$USER_HOME/.local/share/notifoll/venv/bin/python"
if [ ! -x "$VENV_PYTHON" ]; then
    echo "Error: No se encuentra el entorno virtual en $VENV_PYTHON" >&2
    exit 1
fi

# Buscar el script Python (puede estar en diferentes versiones)
SCRIPT_PATH=$(find "$USER_HOME/.local/share/notifoll/venv/lib" -name "notifoll-service.py" 2>/dev/null | head -1)
if [ -z "$SCRIPT_PATH" ]; then
    echo "Error: No se encuentra notifoll-service.py" >&2
    exit 1
fi

# Variables de entorno necesarias
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="$USER_HOME/.config/notifoll/Xauthority"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
fi

exec "$VENV_PYTHON" "$SCRIPT_PATH" "$@"
'
echo "$WRAPPER_CONTENT" | sudo tee /usr/local/bin/notifoll-service > /dev/null
sudo chmod +x /usr/local/bin/notifoll-service
echo "✅ Wrapper creado en /usr/local/bin/notifoll-service"

# Copiar script Fish como comando principal
echo "📦 Copiando notifoll.fish..."
if test -f "notifoll.fish"
    sudo cp notifoll.fish /usr/local/bin/notifoll
    sudo chmod +x /usr/local/bin/notifoll
    echo "✅ Copiado: notifoll.fish → /usr/local/bin/notifoll"
else
    echo $RED"❌ Error: notifoll.fish no encontrado"$NORMAL
    exit 1
end

# Copiar servicio systemd con las variables correctas
echo "📦 Copiando notifoll.service..."
if test -f "notifoll.service"
    # Reemplazar marcadores en el archivo de servicio
    sed -e "s|%USER_HOME%|$HOME|g" \
        -e "s|%SITE_PACKAGES%|$SITE_PACKAGES|g" \
        -e "s|%DISPLAY%|$DISPLAY|g" \
        notifoll.service > ~/.config/systemd/user/notifoll.service
    echo "✅ Copiado: notifoll.service → ~/.config/systemd/user/"
else
    echo $RED"❌ Error: notifoll.service no encontrado"$NORMAL
    exit 1
end

# Crear archivo de configuración por defecto si no existe
if not test -f ~/.config/notifoll/config.json
    echo "📝 Creando configuración por defecto..."
    echo '{
    "prompt_defecto": "Devuelve una respuesta clara y concisa, solo dame la letra del inciso correcto:",
    "modelo": "gemma3:latest",
    "ollama_url": "http://localhost:11434/api/generate",
    "timeout": 120,
    "max_response_length": 300,
    "copy_delay": 0.2,
    "key_trigger": "f8",
    "temperature": 0.7,
    "num_predict": 1000,
    "retry_attempts": 2,
    "retry_delay": 2.0,
    "show_notifications": true,
    "auto_copy": true
}' > ~/.config/notifoll/config.json
end

# Crear autocompletado para Fish
echo "🔌 Instalando autocompletado..."
set COMPLETION_CONTENT '# Completions for notifoll
complete -c notifoll -f

complete -c notifoll -n "not __fish_seen_subcommand_from start stop restart status logs set get list-params test help" -a start -d "Iniciar el servicio"
complete -c notifoll -n "not __fish_seen_subcommand_from start stop restart status logs set get list-params test help" -a stop -d "Detener el servicio"
complete -c notifoll -n "not __fish_seen_subcommand_from start stop restart status logs set get list-params test help" -a restart -d "Reiniciar el servicio"
complete -c notifoll -n "not __fish_seen_subcommand_from start stop restart status logs set get list-params test help" -a status -d "Ver estado del servicio"
complete -c notifoll -n "not __fish_seen_subcommand_from start stop restart status logs set get list-params test help" -a logs -d "Ver logs"
complete -c notifoll -n "not __fish_seen_subcommand_from start stop restart status logs set get list-params test help" -a set -d "Cambiar configuración"
complete -c notifoll -n "not __fish_seen_subcommand_from start stop restart status logs set get list-params test help" -a get -d "Ver configuración"
complete -c notifoll -n "not __fish_seen_subcommand_from start stop restart status logs set get list-params test help" -a list-params -d "Listar parámetros"
complete -c notifoll -n "not __fish_seen_subcommand_from start stop restart status logs set get list-params test help" -a test -d "Probar configuración"
complete -c notifoll -n "not __fish_seen_subcommand_from start stop restart status logs set get list-params test help" -a help -d "Mostrar ayuda"

complete -c notifoll -n "__fish_seen_subcommand_from set" -a "prompt_defecto modelo ollama_url timeout max_response_length copy_delay key_trigger temperature num_predict retry_attempts retry_delay show_notifications auto_copy"
complete -c notifoll -n "__fish_seen_subcommand_from get" -a "prompt_defecto modelo ollama_url timeout max_response_length copy_delay key_trigger temperature num_predict retry_attempts retry_delay show_notifications auto_copy"
complete -c notifoll -n "__fish_seen_subcommand_from logs" -s f -l follow -d "Seguir logs en tiempo real"
complete -c notifoll -n "__fish_seen_subcommand_from logs" -s n -d "Número de líneas a mostrar"
'
echo "$COMPLETION_CONTENT" > ~/.config/fish/completions/notifoll.fish

# Configurar Xauthority para el servicio
echo "🖥️  Configurando X11 para el servicio..."
set -l DISPLAY_NUM (echo $DISPLAY)
if test -z "$DISPLAY_NUM"
    set DISPLAY_NUM ":0"
end

# Obtener magic cookie y crear Xauthority
if command -v xauth > /dev/null
    # Intentar obtener magic cookie actual
    set MAGIC_COOKIE (xauth list $DISPLAY_NUM 2>/dev/null | head -1 | awk '{print $3}')
    if test -z "$MAGIC_COOKIE"
        echo $YELLOW"⚠️  No se pudo obtener magic cookie. Generando una nueva..."$NORMAL
        xauth generate $DISPLAY_NUM . trusted 2>/dev/null
        set MAGIC_COOKIE (xauth list $DISPLAY_NUM 2>/dev/null | head -1 | awk '{print $3}')
    end

    if not test -z "$MAGIC_COOKIE"
        mkdir -p ~/.config/notifoll
        rm -f ~/.config/notifoll/Xauthority
        xauth -f ~/.config/notifoll/Xauthority add $DISPLAY_NUM . $MAGIC_COOKIE
        chmod 600 ~/.config/notifoll/Xauthority
        echo $GREEN"✅ Archivo Xauthority creado: ~/.config/notifoll/Xauthority"$NORMAL
    else
        echo $RED"❌ No se pudo generar magic cookie. Puede que necesites ejecutar 'xauth generate \$DISPLAY .'"$NORMAL
    end
else
    echo $YELLOW"⚠️  xauth no instalado. Instálalo con el gestor de paquetes de tu distro"$NORMAL
end

# Actualizar el archivo de servicio para usar este Xauthority (ya lo hicimos con sed)
# Asegurar que la línea XAUTHORITY apunte al archivo correcto
sed -i "s|%h/.Xauthority|%h/.config/notifoll/Xauthority|" ~/.config/systemd/user/notifoll.service

# Recargar systemd
echo "🔄 Recargando systemd..."
systemctl --user daemon-reload

# Habilitar e iniciar servicio
echo "🚀 Habilitando servicio..."
systemctl --user enable notifoll
systemctl --user start notifoll

# Verificar estado
sleep 2
set -l service_state (systemctl --user is-active notifoll 2>/dev/null)
switch "$service_state"
    case active
        echo $GREEN"✅ Servicio iniciado correctamente"$NORMAL
    case '*'
        echo $RED"❌ Error iniciando servicio"$NORMAL
        echo "Estado: $service_state"
        systemctl --user status notifoll --no-pager -l
        echo ""
        echo "📋 Para ver más detalles:"
        echo "  journalctl --user -u notifoll -n 50"
end

# Smoke test post-instalación con autorreparación X11
echo ""
echo "🧪 Ejecutando smoke test post-instalación..."
if run_smoke_test
    echo $GREEN"✅ Smoke test aprobado"$NORMAL
else
    echo $YELLOW"⚠️  Smoke test falló. Intentando autoreparación con fixx11complete.fish..."$NORMAL
    if test -f "$SCRIPT_DIR/fixx11complete.fish"
        chmod +x "$SCRIPT_DIR/fixx11complete.fish"
        fish "$SCRIPT_DIR/fixx11complete.fish"
        sleep 2
        echo ""
        echo "🔁 Reintentando smoke test..."
        if run_smoke_test
            echo $GREEN"✅ Smoke test aprobado después de autoreparación"$NORMAL
        else
            echo $RED"❌ Smoke test sigue fallando después de autoreparación"$NORMAL
            echo "📋 Revisa logs con: journalctl --user -u notifoll -n 100 --no-pager"
        end
    else
        echo $YELLOW"⚠️  No se encontró $SCRIPT_DIR/fixx11complete.fish, no se pudo autorreparar"$NORMAL
    end
end

# Verificar grupo input
if not groups | grep -q input
    echo ""
    echo $YELLOW"⚠️  El usuario no pertenece al grupo 'input'."$NORMAL
    echo "   Para que el listener de teclado funcione globalmente, ejecuta:"
    echo "   sudo usermod -aG input $USER"
    echo "   Luego CIERRA SESIÓN Y VUELVE A ENTRAR (o reinicia)."
end

# Alias opcional
echo ""
echo "📝 ¿Quieres crear un alias 'nf' para notifoll? (s/n)"
read -l create_alias
if contains s S $create_alias
    if not grep -q "alias nf=" ~/.config/fish/config.fish 2>/dev/null
        echo "alias nf='notifoll'" >> ~/.config/fish/config.fish
        echo $GREEN"✅ Alias 'nf' creado. Ejecuta 'source ~/.config/fish/config.fish'"$NORMAL
    else
        echo $YELLOW"⚠️  El alias 'nf' ya existe en config.fish"$NORMAL
    end
end

echo ""
echo $GREEN"=================================="$NORMAL
echo $GREEN"✅ Instalación completa!"$NORMAL
echo $GREEN"=================================="$NORMAL
echo ""
echo "Comandos disponibles:"
echo "  notifoll start              - Iniciar servicio"
echo "  notifoll stop               - Detener servicio"
echo "  notifoll status             - Ver estado"
echo "  notifoll logs -f            - Ver logs en tiempo real"
echo "  notifoll set modelo llama2  - Cambiar modelo"
echo "  notifoll get                - Ver configuración"
echo "  notifoll list-params        - Ver todos los parámetros"
echo ""
echo "Configuración en: ~/.config/notifoll/config.json"
echo "Logs: journalctl --user -u notifoll -f"
echo ""
echo "🎯 Para usar: selecciona texto y presiona F8"
