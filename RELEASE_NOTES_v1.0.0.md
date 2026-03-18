# Notifoll v1.0.0

Fecha: 2026-03-18

## Resumen

Primera versión estable de Notifoll con instalación guiada, servicio systemd user, configuración dinámica y flujo automático de diagnóstico/recuperación.

## Cambios principales

- Instalador multi-distro con detección de gestor de paquetes:
  - `pacman`, `apt`, `dnf`, `yum`, `zypper`, `apk`, `xbps-install`, `emerge`
- Instalación de dependencias de sistema y Python en `venv`.
- Wrapper `/usr/local/bin/notifoll-service` con variables de entorno para X11/Wayland.
- Servicio user de systemd (`notifoll.service`) y comando CLI `notifoll`.
- Smoke test post-instalación automático.
- Autorreparación X11 automática ejecutando `fixx11complete.fish` cuando el smoke test falla.
- Script de desinstalación con purga opcional de dependencias del sistema.
- Documentación completa en `README.md`.
- Licencia MIT agregada.

## Compatibilidad validada

- KDE en X11
- GNOME en X11

Nota: en Wayland, la captura global de teclado puede depender de restricciones del compositor.

## Upgrade desde versiones previas

1. Ejecutar `./uninstall.fish` (conservar o borrar configuración según prefieras).
2. Actualizar repositorio:
   - `git pull`
3. Reinstalar:
   - `./install.fish`

## Verificación recomendada

- `systemctl --user status notifoll`
- `journalctl --user -u notifoll -n 50 --no-pager`
- Seleccionar texto y presionar `F8`
