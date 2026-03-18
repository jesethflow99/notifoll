# Notifoll

Notifoll es un helper para Linux que captura texto seleccionado con una tecla global (por defecto `F8`), lo envía a Ollama, y muestra/copia la respuesta automáticamente.

Está pensado para usarse en escritorio con **Fish Shell**, como **servicio de usuario de systemd**.

Repositorio oficial: `https://github.com/jesethflow99/notifoll`

## Características

- Atajo global configurable (`key_trigger`, por defecto `f8`).
- Copia texto seleccionado (`Ctrl+C`) y lo procesa con Ollama.
- Notificaciones de escritorio con la respuesta.
- Copia automática de la respuesta al portapapeles.
- Configuración dinámica en `~/.config/notifoll/config.json`.
- Comando CLI `notifoll` para gestionar servicio y parámetros.

## Requisitos

- Linux con `systemd --user`.
- Fish Shell.
- Python 3 + `venv`.
- Ollama instalado y ejecutándose.
- X11/entorno gráfico funcional (`DISPLAY`, `XAUTHORITY`).

Dependencias de sistema que instala automáticamente el script:

- `libnotify` (`notify-send`)
- `xclip`
- `xdotool` (opcional)
- `xauth` (recomendado para X11)
- `wl-clipboard` (recomendado para Wayland)

Dependencias Python instaladas en venv:

- `pyperclip`
- `pynput`
- `requests`
- `watchdog`

## Instalación

Instalación rápida desde GitHub:

```bash
git clone https://github.com/jesethflow99/notifoll.git
cd notifoll
chmod +x install.fish
./install.fish
```

Desde la raíz del proyecto:

```fish
chmod +x install.fish
./install.fish
```

El instalador:

- crea entorno virtual en `~/.local/share/notifoll/venv`
- instala dependencias Python
- instala binarios en `/usr/local/bin/`
- instala servicio en `~/.config/systemd/user/notifoll.service`
- crea config por defecto en `~/.config/notifoll/config.json`
- habilita e inicia el servicio `notifoll`
- ejecuta un smoke test post-instalación y, si falla, intenta reparación automática con `fixx11complete.fish`

Gestores de paquetes soportados por detección automática:

- `pacman` (Arch/Manjaro)
- `apt` (Debian/Ubuntu)
- `dnf`/`yum` (Fedora/RHEL)
- `zypper` (openSUSE)
- `apk` (Alpine)
- `xbps-install` (Void)
- `emerge` (Gentoo)

## Uso rápido

1. Asegúrate de que Ollama esté levantado:

```bash
ollama serve
```

2. Verifica servicio:

```fish
notifoll status
```

3. Selecciona texto en cualquier app y presiona `F8`.

4. Revisa notificación y portapapeles (si `auto_copy=true`).

## Comandos CLI

```fish
notifoll start
notifoll stop
notifoll restart
notifoll status
notifoll logs -f
notifoll set modelo llama3
notifoll get
notifoll get modelo
notifoll list-params
notifoll test
notifoll help
```

## Configuración

Archivo: `~/.config/notifoll/config.json`

Parámetros principales:

- `prompt_defecto` (string): prompt base para Ollama.
- `modelo` (string): modelo a usar, ej. `gemma3:latest`.
- `ollama_url` (string): endpoint API, por defecto `http://localhost:11434/api/generate`.
- `timeout` (int): timeout base por intento.
- `max_response_length` (int): longitud máxima de texto en notificación.
- `copy_delay` (float): espera tras simular `Ctrl+C`.
- `key_trigger` (string): tecla de activación (`f1`..`f12`).
- `temperature` (float): temperatura del modelo (0 a 2).
- `num_predict` (int): tokens máximos.
- `retry_attempts` (int): reintentos ante fallo.
- `retry_delay` (float): espera entre reintentos.
- `show_notifications` (bool): mostrar notificaciones del sistema.
- `auto_copy` (bool): copiar respuesta al portapapeles.

Ejemplos:

```fish
notifoll set modelo gemma3:latest
notifoll set key_trigger f9
notifoll set timeout 180
notifoll set show_notifications true
```

## Logs y diagnóstico

Ver logs del servicio:

```bash
journalctl --user -u notifoll -f
```

Si hay problemas con X11 o notificaciones, ejecuta:

```fish
chmod +x fixx11complete.fish
./fixx11complete.fish
```

## Problemas comunes

- **No detecta tecla global**: agrega tu usuario al grupo `input` y vuelve a iniciar sesión.
  ```bash
  sudo usermod -aG input $USER
  ```
- **No conecta a Ollama**: verifica `ollama serve` y modelos instalados (`ollama list`).
- **No muestra notificaciones**: valida `DISPLAY`, `DBUS_SESSION_BUS_ADDRESS` y archivo `~/.config/notifoll/Xauthority`.
- **Wayland y atajo global**: en algunos compositores, los hooks globales de teclado están restringidos. El wrapper ya exporta variables Wayland/X11, pero la captura global puede requerir permisos extra o no estar permitida.

## Desinstalación

```fish
chmod +x uninstall.fish
./uninstall.fish
```

El script detiene servicio, elimina binarios y entorno virtual, y opcionalmente:

- borra configuración (`~/.config/notifoll`)
- elimina dependencias del sistema (con confirmación y advertencia)

## Estructura del proyecto

- `notifoll-service.py`: servicio principal (captura teclado, portapapeles, llamada a Ollama).
- `notifoll.fish`: CLI para control y configuración.
- `notifoll.service`: unidad base de systemd user.
- `install.fish`: instalación completa.
- `uninstall.fish`: desinstalación.
- `fixx11complete.fish`: reparación de entorno X11/systemd.

## Nota

El instalador ya no depende de una sola distro: detecta el gestor de paquetes y usa nombres equivalentes para instalar dependencias. Si tu distro usa otro gestor, el script te mostrará qué paquetes instalar manualmente.
