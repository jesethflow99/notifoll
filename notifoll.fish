#!/usr/bin/env fish
# /usr/local/bin/notifoll.fish - Interfaz de línea de comandos mejorada

set CONFIG_FILE "$HOME/.config/notifoll/config.json"
set PID_FILE "/tmp/notifoll.pid"

function show_help
    echo "Uso: notifoll [comando] [argumentos]"
    echo ""
    echo "Comandos:"
    echo "  start                     Iniciar el servicio en segundo plano"
    echo "  stop                      Detener el servicio"
    echo "  restart                   Reiniciar el servicio"
    echo "  status                    Ver estado del servicio"
    echo "  logs                      Ver últimos logs"
    echo "  set <param> <valor>       Cambiar un parámetro de configuración"
    echo "  get [param]               Ver configuración (todos o uno específico)"
    echo "  list-params               Listar todos los parámetros disponibles"
    echo "  test                      Probar la configuración actual"
    echo "  help                      Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  notifoll set prompt_defecto \"resume este texto:\""
    echo "  notifoll set modelo llama2"
    echo "  notifoll set timeout 30"
    echo "  notifoll get modelo"
    echo "  notifoll logs -f          Ver logs en tiempo real"
    echo ""
    echo "Parámetros disponibles:"
    echo "  prompt_defecto    : Prompt por defecto para Ollama"
    echo "  modelo           : Modelo de Ollama a usar"
    echo "  ollama_url       : URL de la API de Ollama"
    echo "  timeout          : Timeout en segundos"
    echo "  max_response_length: Longitud máxima de respuesta"
    echo "  copy_delay       : Delay para copiar texto"
    echo "  key_trigger      : Tecla de activación"
    echo "  temperature      : Temperatura del modelo"
    echo "  num_predict      : Número máximo de tokens"
    echo "  retry_attempts   : Intentos de reintento"
    echo "  retry_delay      : Delay entre reintentos"
    echo "  show_notifications: Mostrar notificaciones (true/false)"
    echo "  auto_copy        : Auto-copiar respuesta (true/false)"
end

function validate_param
    set param $argv[1]
    set value $argv[2]
    
    switch $param
        case timeout max_response_length num_predict retry_attempts
            if not string match -q -r '^[0-9]+$' $value
                echo "Error: $param debe ser un número entero"
                return 1
            end
        case retry_delay copy_delay
            if not string match -q -r '^[0-9]*\.?[0-9]+$' $value
                echo "Error: $param debe ser un número"
                return 1
            end
        case temperature
            # Validar que sea un número entre 0 y 2 usando math de fish
            if not string match -q -r '^[0-9]*\.?[0-9]+$' $value
                echo "Error: temperature debe ser un número"
                return 1
            end
            # Usar math para comparar rangos (fish 3.1+)
            if test (math "$value < 0" 2>/dev/null) -eq 1 -o (math "$value > 2" 2>/dev/null) -eq 1
                echo "Error: temperature debe ser un número entre 0 y 2"
                return 1
            end
        case show_notifications auto_copy
            if not contains $value true false
                echo "Error: $param debe ser true o false"
                return 1
            end
    end
    return 0
end

# Función para manejar tipos en Python
function update_config_python
    set param $argv[1]
    set value $argv[2]
    
    python3 -c "
import json
import os
import sys

config_file = '$CONFIG_FILE'
param = '$param'
value = '$value'

try:
    # Convertir tipos apropiados
    if param in ['timeout', 'max_response_length', 'num_predict', 'retry_attempts']:
        value = int(value)
    elif param in ['temperature', 'retry_delay', 'copy_delay']:
        value = float(value)
    elif param in ['show_notifications', 'auto_copy']:
        value = value.lower() == 'true'
    
    # Cargar o crear config
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            config = json.load(f)
    else:
        config = {}
    
    # Actualizar
    config[param] = value
    
    # Guardar
    os.makedirs(os.path.dirname(config_file), exist_ok=True)
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=4)
    
    print(f'✅ Parámetro {param} actualizado a: {value}')
    sys.exit(0)
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
"
end

# Procesar comandos
switch $argv[1]
    case start
        echo "Iniciando notifoll..."
        if test -f "$PID_FILE"; and kill -0 (cat $PID_FILE) 2>/dev/null
            echo "El servicio ya está en ejecución"
        else
            systemctl --user start notifoll
            echo "Servicio iniciado"
        end
        
    case stop
        echo "Deteniendo notifoll..."
        systemctl --user stop notifoll
        if test -f "$PID_FILE"
            rm $PID_FILE
        end
        echo "Servicio detenido"
        
    case restart
        echo "Reiniciando notifoll..."
        systemctl --user restart notifoll
        echo "Servicio reiniciado"
        
    case status
        systemctl --user status notifoll
        
    case logs
        set -l args $argv[2..-1]
        journalctl --user -u notifoll $args
        
    case set
        if test (count $argv) -lt 3
            echo "Error: Se requieren parámetro y valor"
            echo "Uso: notifoll set <param> <valor>"
            exit 1
        end
        
        set param $argv[2]
        set value $argv[3]
        
        if not validate_param $param $value
            exit 1
        end
        
        # Crear backup de la configuración
        if test -f "$CONFIG_FILE"
            cp $CONFIG_FILE $CONFIG_FILE.backup
        end
        
        # Actualizar configuración usando Python
        if not update_config_python $param $value
            exit 1
        end
        
        # Preguntar si reiniciar el servicio
        echo "¿Reiniciar el servicio para aplicar cambios? (s/n)"
        read -l answer
        if contains $answer s S
            systemctl --user restart notifoll
            echo "Servicio reiniciado"
        end
        
    case get
        if test -f "$CONFIG_FILE"
            if test (count $argv) -ge 2
                set param $argv[2]
                python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)
print(config.get('$param', 'Parámetro no encontrado'))
"
            else
                cat $CONFIG_FILE | python3 -m json.tool
            end
        else
            echo "Archivo de configuración no encontrado"
        end
        
    case list-params
        echo "Parámetros disponibles:"
        echo "  prompt_defecto    : String - Prompt por defecto"
        echo "  modelo           : String - Nombre del modelo"
        echo "  ollama_url       : String - URL de Ollama"
        echo "  timeout          : Number - Timeout en segundos"
        echo "  max_response_length: Number - Longitud máxima de respuesta"
        echo "  copy_delay       : Number - Delay de copia (segundos)"
        echo "  key_trigger      : String - Tecla de activación"
        echo "  temperature      : Number - Temperatura del modelo (0-2)"
        echo "  num_predict      : Number - Máximo de tokens"
        echo "  retry_attempts   : Number - Intentos de reintento"
        echo "  retry_delay      : Number - Delay entre reintentos"
        echo "  show_notifications: Boolean - Mostrar notificaciones"
        echo "  auto_copy        : Boolean - Auto-copiar respuesta"
        
    case test
        echo "Probando configuración..."
        python3 -c "
import json
import sys
from pathlib import Path

config_file = Path('$CONFIG_FILE')
if config_file.exists():
    with open(config_file, 'r') as f:
        config = json.load(f)
    print('✅ Configuración válida:')
    for k, v in config.items():
        print(f'  {k}: {v}')
else:
    print('❌ Archivo de configuración no encontrado')
    sys.exit(1)
"
        
    case help ''
        show_help
        
    case '*'
        echo "Comando desconocido: $argv[1]"
        show_help
        exit 1
end