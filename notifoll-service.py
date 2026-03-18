#!/usr/bin/env python3
"""
Notifoll - Servicio de procesamiento de texto con Ollama
Ejecuta como servicio systemd y permite configuración dinámica
Versión para Fish Shell
"""

import pyperclip
from pynput import keyboard
import requests
import subprocess
import time
import json
import logging
import sys
import os
import signal
from pathlib import Path
from typing import Optional, Dict, Any, Tuple
from dataclasses import dataclass, asdict
from requests.exceptions import RequestException, Timeout, ConnectionError
import threading
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Configuración de paths
CONFIG_DIR = Path.home() / ".config" / "notifoll"
CONFIG_PATH = CONFIG_DIR / "config.json"
PID_FILE = Path("/tmp") / "notifoll.pid"

# Asegurar que existe el directorio de configuración
CONFIG_DIR.mkdir(parents=True, exist_ok=True)

# Configuración de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)  # systemd capturará esto
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class Config:
    """Configuración de la aplicación"""
    prompt_defecto: str = "Devuelve una respuesta clara y concisa, solo dame la letra del inciso correcto:"
    modelo: str = "gemma3:latest"
    ollama_url: str = "http://localhost:11434/api/generate"
    timeout: int = 120
    max_response_length: int = 300
    copy_delay: float = 0.2
    key_trigger: str = "f8"
    temperature: float = 0.7
    num_predict: int = 1000
    retry_attempts: int = 2
    retry_delay: float = 2.0
    show_notifications: bool = True
    auto_copy: bool = True
    
    @classmethod
    def from_file(cls, config_path: Path) -> 'Config':
        """Carga configuración desde archivo JSON"""
        # Valores por defecto
        config_dict = {
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
            "show_notifications": True,
            "auto_copy": True
        }
        
        if config_path.exists():
            try:
                with open(config_path, "r", encoding="utf-8") as f:
                    user_config = json.load(f)
                    # Actualizar solo las claves que existen en el dict por defecto
                    for key in user_config:
                        if key in config_dict:
                            config_dict[key] = user_config[key]
                        else:
                            logger.warning(f"Clave de configuración desconocida: {key}")
                logger.info(f"Configuración cargada desde {config_path}")
            except (json.JSONDecodeError, IOError) as e:
                logger.error(f"Error cargando configuración: {e}")
        else:
            # Crear archivo de configuración por defecto
            try:
                with open(config_path, "w", encoding="utf-8") as f:
                    json.dump(config_dict, f, indent=4, ensure_ascii=False)
                logger.info(f"Archivo de configuración creado en {config_path}")
            except IOError as e:
                logger.error(f"No se pudo crear archivo de configuración: {e}")
        
        return cls(**config_dict)
    
    def save(self):
        """Guarda la configuración actual"""
        try:
            with open(CONFIG_PATH, "w", encoding="utf-8") as f:
                json.dump(asdict(self), f, indent=4, ensure_ascii=False)
            logger.info("Configuración guardada")
        except Exception as e:
            logger.error(f"Error guardando configuración: {e}")

class ConfigFileHandler(FileSystemEventHandler):
    """Manejador de cambios en el archivo de configuración"""
    
    def __init__(self, app):
        self.app = app
        self.last_reload = 0
        self.cooldown = 2  # segundos
    
    def on_modified(self, event):
        if event.src_path == str(CONFIG_PATH):
            current_time = time.time()
            if current_time - self.last_reload > self.cooldown:
                logger.info("Archivo de configuración modificado, recargando...")
                self.last_reload = current_time
                self.app.reload_config()

class ClipboardManager:
    """Maneja operaciones del portapapeles"""
    
    def __init__(self, copy_delay: float = 0.2):
        self.copy_delay = copy_delay
        self.controller = keyboard.Controller()
    
    def get_selected_text(self) -> Optional[str]:
        """Copia el texto seleccionado y lo retorna"""
        # Guardar contenido actual del portapapeles
        try:
            old_content = pyperclip.paste()
        except:
            old_content = ""
        
        # Limpiar portapapeles
        try:
            pyperclip.copy("")
            time.sleep(0.05)
        except:
            pass
        
        # Simular Ctrl+C
        try:
            with self.controller.pressed(keyboard.Key.ctrl):
                self.controller.tap('c')
        except Exception as e:
            logger.error(f"Error simulando Ctrl+C: {e}")
            return None
        
        time.sleep(self.copy_delay)
        
        try:
            texto = pyperclip.paste().strip()
        except:
            texto = ""
        
        # Restaurar contenido anterior si no hay texto nuevo
        if not texto:
            try:
                pyperclip.copy(old_content)
            except:
                pass
            logger.debug("No se detectó texto en el portapapeles")
            return None
        
        logger.debug(f"Texto copiado ({len(texto)} chars)")
        return texto

class OllamaClient:
    """Cliente para interactuar con Ollama con manejo mejorado de errores"""
    
    def __init__(self, config: Config):
        self.config = config
        self.session = requests.Session()
        # Configurar timeouts por defecto para la sesión
        self.session.timeout = config.timeout
    
    def check_ollama_status(self) -> Tuple[bool, str]:
        """Verifica si Ollama está accesible y qué modelos están disponibles"""
        try:
            response = requests.get("http://localhost:11434/api/tags", timeout=5)
            if response.status_code == 200:
                models = response.json().get('models', [])
                model_names = [m.get('name') for m in models]
                
                # Verificar si el modelo está disponible (con o sin :latest)
                model_to_check = self.config.modelo
                if not ':' in model_to_check:
                    model_to_check = f"{model_to_check}:latest"
                
                model_found = False
                for m in model_names:
                    if m == model_to_check or m.startswith(self.config.modelo.split(':')[0]):
                        model_found = True
                        break
                
                if model_found:
                    return True, f"Ollama conectado. Modelo {self.config.modelo} disponible"
                else:
                    return False, f"Ollama conectado pero modelo {self.config.modelo} no encontrado. Modelos disponibles: {', '.join(model_names[:5])}"
            return False, "Ollama no responde correctamente"
        except ConnectionError:
            return False, "No se puede conectar a Ollama. ¿Está ejecutándose? (comando: 'ollama serve')"
        except Timeout:
            return False, "Timeout al conectar con Ollama"
        except Exception as e:
            return False, f"Error verificando Ollama: {e}"
    
    def process_text_with_retry(self, text: str) -> str:
        """Envía texto a Ollama con reintentos"""
        prompt = self.config.prompt_defecto
        payload = {
            "model": self.config.modelo,
            "prompt": f"{prompt}\n\n{text}",
            "stream": False,
            "options": {
                "temperature": self.config.temperature,
                "num_predict": self.config.num_predict
            }
        }
        
        for attempt in range(self.config.retry_attempts + 1):
            try:
                # Usar timeout más largo para cada intento
                timeout = self.config.timeout * (attempt + 1)
                
                logger.info(f"Enviando solicitud a Ollama (intento {attempt + 1}/{self.config.retry_attempts + 1})")
                response = self.session.post(
                    self.config.ollama_url,
                    json=payload,
                    timeout=timeout
                )
                response.raise_for_status()
                
                result = response.json().get("response", "Sin respuesta")
                logger.info(f"Respuesta recibida ({len(result)} chars)")
                return result
                
            except Timeout as e:
                error_msg = f"Timeout en intento {attempt + 1}"
                logger.warning(error_msg)
                
                if attempt < self.config.retry_attempts:
                    wait_time = self.config.retry_delay * (attempt + 1)
                    logger.info(f"Reintentando en {wait_time} segundos...")
                    time.sleep(wait_time)
                else:
                    return f"""Error después de {self.config.retry_attempts + 1} intentos: Tiempo de espera agotado.
                    
El modelo puede estar tardando más de lo esperado. Considera:
• Aumentar 'timeout' en la configuración
• Usar un modelo más rápido
• Verificar que Ollama tenga suficientes recursos

Comando: notifoll set timeout 180"""
                    
            except ConnectionError as e:
                logger.warning(f"Error de conexión: {e}")
                if attempt < self.config.retry_attempts:
                    logger.info(f"Reintentando en {self.config.retry_delay} segundos...")
                    time.sleep(self.config.retry_delay)
                else:
                    return """Error: No se pudo conectar con Ollama.

Asegúrate de que:
• Ollama esté ejecutándose (comando: 'ollama serve')
• El modelo esté descargado (comando: 'ollama pull gemma3')
• No haya firewalls bloqueando el puerto 11434

Verifica con: curl http://localhost:11434/api/tags"""
                    
            except RequestException as e:
                logger.error(f"Error en la petición: {e}")
                if hasattr(e.response, 'text'):
                    logger.error(f"Respuesta del servidor: {e.response.text}")
                return f"Error en la comunicación: {str(e)[:150]}"
                
            except json.JSONDecodeError as e:
                logger.error(f"Error decodificando JSON: {e}")
                return "Error: Respuesta inválida del servidor. Puede ser un problema temporal, intenta de nuevo."
                
            except Exception as e:
                logger.error(f"Error inesperado: {e}")
                return f"Error inesperado: {str(e)[:150]}"
        
        return "Error: No se pudo procesar la solicitud después de múltiples intentos"

class Notifier:
    """Maneja las notificaciones del sistema"""
    
    def __init__(self, enabled: bool = True):
        self.enabled = enabled
    
    def notify(self, title: str, message: str, max_length: int = 300, error: bool = False) -> None:
        """Envía una notificación al sistema"""
        if not self.enabled:
            log_level = logging.ERROR if error else logging.INFO
            logger.log(log_level, f"[{title}] {message}")
            return
        
        if len(message) > max_length:
            message = message[:max_length] + "..."
        
        message = ' '.join(message.split())
        
        icon = "dialog-error" if error else "dialog-information"
        urgency = "critical" if error else "normal"
        
        try:
            subprocess.run(
                ['notify-send', 
                 '--icon', icon,
                 '--urgency', urgency,
                 '--expire-time', '5000',
                 title, 
                 message],
                timeout=2,
                check=False
            )
        except (subprocess.TimeoutExpired, FileNotFoundError):
            print(f"\n[{title}] {message}")

class TextProcessorApp:
    """Aplicación principal como servicio"""
    
    def __init__(self):
        # Verificar entorno
        self.verify_environment()
        
        # Cargar configuración
        self.config = Config.from_file(CONFIG_PATH)
        
        # Inicializar componentes
        self.clipboard = None
        self.ollama = None
        self.notifier = None
        self.running = True
        self.processing = False
        self.listener = None
        self.observer = None
        
        # Mapeo de teclas
        self.key_map = {
            'f1': keyboard.Key.f1,
            'f2': keyboard.Key.f2,
            'f3': keyboard.Key.f3,
            'f4': keyboard.Key.f4,
            'f5': keyboard.Key.f5,
            'f6': keyboard.Key.f6,
            'f7': keyboard.Key.f7,
            'f8': keyboard.Key.f8,
            'f9': keyboard.Key.f9,
            'f10': keyboard.Key.f10,
            'f11': keyboard.Key.f11,
            'f12': keyboard.Key.f12,
        }
        
        # Inicializar componentes con la configuración
        self.reload_config(full_reload=True)
        
        # Guardar PID
        try:
            with open(PID_FILE, "w") as f:
                f.write(str(os.getpid()))
        except Exception as e:
            logger.error(f"No se pudo guardar PID: {e}")
        
        # Configurar manejador de señales
        signal.signal(signal.SIGTERM, self.signal_handler)
        signal.signal(signal.SIGINT, self.signal_handler)
        
        # Iniciar watcher de configuración
        self.start_config_watcher()
    
    def verify_environment(self):
        """Verifica compatibilidad con el entorno"""
        if os.environ.get('XDG_SESSION_TYPE') == 'wayland':
            logger.warning("Sesión Wayland detectada: el atajo global puede no funcionar según compositor/permisos.")

        if 'FISH_VERSION' in os.environ:
            logger.info("🐟 Detectado Fish shell")
        
        if not os.environ.get('DISPLAY'):
            logger.warning("Variable DISPLAY no configurada. Las notificaciones pueden no funcionar.")
        
        if not os.environ.get('XAUTHORITY'):
            logger.debug("XAUTHORITY no configurada, usando valor por defecto")
    
    def reload_config(self, full_reload=False):
        """Recarga la configuración"""
        old_config = self.config
        self.config = Config.from_file(CONFIG_PATH)
        
        if full_reload:
            self.clipboard = ClipboardManager(self.config.copy_delay)
            self.ollama = OllamaClient(self.config)
            self.notifier = Notifier(self.config.show_notifications)
        else:
            if old_config.copy_delay != self.config.copy_delay:
                self.clipboard.copy_delay = self.config.copy_delay
            
            if old_config.show_notifications != self.config.show_notifications:
                self.notifier.enabled = self.config.show_notifications
            
            if (old_config.modelo != self.config.modelo or
                old_config.ollama_url != self.config.ollama_url or
                old_config.timeout != self.config.timeout):
                self.ollama = OllamaClient(self.config)
        
        logger.info("Configuración recargada")
        
        status, message = self.ollama.check_ollama_status()
        if status:
            logger.info(f"✅ {message}")
        else:
            logger.warning(f"⚠️ {message}")
    
    def start_config_watcher(self):
        """Inicia el observador de cambios en configuración"""
        try:
            self.observer = Observer()
            event_handler = ConfigFileHandler(self)
            self.observer.schedule(event_handler, str(CONFIG_DIR), recursive=False)
            self.observer.start()
            logger.info("Observador de configuración iniciado")
        except Exception as e:
            logger.error(f"No se pudo iniciar observador de configuración: {e}")
    
    def signal_handler(self, signum, frame):
        """Manejador de señales para cierre graceful"""
        signal_names = {signal.SIGTERM: "SIGTERM", signal.SIGINT: "SIGINT"}
        logger.info(f"Señal {signal_names.get(signum, str(signum))} recibida, cerrando servicio...")
        self.cleanup()
        sys.exit(0)
    
    def handle_key(self, key):
        """Maneja eventos de teclado"""
        try:
            trigger_key = self.key_map.get(self.config.key_trigger.lower())
            if trigger_key and key == trigger_key and self.running and not self.processing:
                logger.info(f"Tecla {self.config.key_trigger.upper()} presionada")
                thread = threading.Thread(target=self.process_selected_text)
                thread.daemon = True
                thread.start()
        except AttributeError:
            pass
        except Exception as e:
            logger.error(f"Error manejando tecla: {e}")
    
    def process_selected_text(self):
        """Procesa el texto seleccionado"""
        self.processing = True
        
        try:
            status, message = self.ollama.check_ollama_status()
            if not status:
                self.notifier.notify("Ollama - Error", message, error=True)
                return
            
            texto = self.clipboard.get_selected_text()
            
            if not texto:
                self.notifier.notify("Ollama", "No se detectó texto seleccionado. Asegúrate de seleccionar texto antes de presionar F8.", error=True)
                return
            
            logger.info(f"Procesando texto ({len(texto)} chars)")
            
            respuesta = self.ollama.process_text_with_retry(texto)
            
            if self.config.auto_copy and not respuesta.startswith("Error"):
                try:
                    pyperclip.copy(respuesta)
                    logger.info("Respuesta copiada al portapapeles")
                except Exception as e:
                    logger.error(f"Error copiando al portapapeles: {e}")
            
            self.notifier.notify(
                "Ollama - Respuesta", 
                respuesta, 
                self.config.max_response_length,
                error=respuesta.startswith("Error")
            )
            
        except Exception as e:
            logger.error(f"Error inesperado procesando texto: {e}")
            self.notifier.notify("Ollama - Error", f"Error inesperado: {str(e)[:100]}", error=True)
        finally:
            self.processing = False
    
    def run(self):
        """Ejecuta el servicio"""
        logger.info("🚀 Servicio notifoll iniciado")
        logger.info(f"⚙️ Configuración actual:")
        for key, value in asdict(self.config).items():
            logger.info(f"   • {key}: {value}")
        
        status, message = self.ollama.check_ollama_status()
        if status:
            logger.info(f"✅ {message}")
            self.notifier.notify("Ollama Helper", "Servicio iniciado correctamente", error=False)
        else:
            logger.warning(f"⚠️ {message}")
            self.notifier.notify("Ollama Helper - Advertencia", message, error=True)
        
        try:
            with keyboard.Listener(on_press=self.handle_key) as listener:
                self.listener = listener
                listener.join()
        except OSError as e:
            logger.error(f"Error al crear listener de teclado: {e}")
            logger.error("Asegúrate de tener permisos para acceder a los dispositivos de entrada. Debes pertenecer al grupo 'input'.")
            self.notifier.notify("Error de permisos", "No se puede acceder al teclado. ¿Estás en el grupo 'input'?", error=True)
            sys.exit(1)
        except Exception as e:
            logger.error(f"Error en el listener: {e}")
            sys.exit(1)
    
    def cleanup(self):
        """Limpieza al finalizar"""
        self.running = False
        if self.listener:
            self.listener.stop()
        if self.observer:
            self.observer.stop()
            self.observer.join()
        if PID_FILE.exists():
            try:
                PID_FILE.unlink()
            except:
                pass
        logger.info("🧹 Servicio detenido correctamente")

def main():
    """Punto de entrada principal"""
    try:
        app = TextProcessorApp()
        app.run()
    except KeyboardInterrupt:
        logger.info("🛑 Servicio detenido por el usuario")
    except Exception as e:
        logger.error(f"Error fatal: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
