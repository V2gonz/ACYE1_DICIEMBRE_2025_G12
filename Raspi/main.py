import time
import board
import adafruit_dht
import RPi.GPIO as GPIO
from rpi_lcd import LCD
import pymongo
import datetime
import paho.mqtt.client as mqtt
import json

# ==========================================
# 1. CONFIGURACIÓN MQTT
# ==========================================
MQTT_BROKER = "broker.emqx.io"
MQTT_PORT = 1883
TOPICO_PUBLICAR = "fiusac/grupo_12/telemetria"
TOPICO_SUSCRIBIR = "fiusac/grupo_12/comandos"

client_mqtt = mqtt.Client()

# ==========================================
# 2. CONFIGURACIÓN MONGODB
# ==========================================
MONGO_URI = "mongodb+srv://admin_fiusac:0306@kiwi-bd.xi6ztan.mongodb.net/?retryWrites=true&w=majority&appName=kiwi-BD"
mongo_ok = False

print("--- INICIANDO SISTEMA FIUSAC V2.0 ---")
print("1. Conectando a Base de Datos...")

try:
    client_mongo = pymongo.MongoClient(MONGO_URI, serverSelectionTimeoutMS=3000)
    client_mongo.server_info()
    db = client_mongo["fiusac_datacenter"]
    collection_temp = db["temperatura"]
    collection_hum = db["humedad"]
    collection_events = db["eventos"]
    mongo_ok = True
    print("   [BD] Conectado Correctamente")
except Exception as e:
    print(f"   [BD] Error: {e}")

# ==========================================
# 3. CONFIGURACIÓN DE PINES
# ==========================================
GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)

PIR_PIN = 17
SERVO_PIN = 18
FAN_PIN = 23
BUZZER_PIN = 27
LEDS_BLANCOS_PIN = 22
BOTON_MANT_PIN = 26

RGB_RED = 5
RGB_GREEN = 6
RGB_BLUE = 13

GPIO.setup(PIR_PIN, GPIO.IN)
GPIO.setup(FAN_PIN, GPIO.OUT)
GPIO.setup(BUZZER_PIN, GPIO.OUT)
GPIO.setup(LEDS_BLANCOS_PIN, GPIO.OUT)
GPIO.setup([RGB_RED, RGB_GREEN, RGB_BLUE], GPIO.OUT)
GPIO.setup(BOTON_MANT_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)

GPIO.setup(SERVO_PIN, GPIO.OUT)
servo_pwm = GPIO.PWM(SERVO_PIN, 50)
servo_pwm.start(0)

dht_device = adafruit_dht.DHT11(board.D4)
try:
    lcd = LCD()
except:
    lcd = None

# ==========================================
# 4. VARIABLES GLOBALES
# ==========================================
TEMP_UMBRAL_FAN = 24
TEMP_UMBRAL_ALERTA = 28
HUM_UMBRAL_ALERTA = 70

puerta_abierta = False
modo_mantenimiento = False

# NUEVAS VARIABLES PARA CONTROL DE VENTILADOR
fan_modo_manual = False # False = Automatico, True = Manual
fan_estado_manual = False # True = ON, False = OFF

# Temporizadores
tiempo_ultimo_log_mongo = 0
INTERVALO_MONGO = 30
tiempo_ultimo_mqtt = 0
INTERVALO_MQTT = 3
ultimo_evento_tipo = ""
tiempo_ultimo_evento = 0

# ==========================================
# 5. FUNCIONES MQTT (Lógica Remota)
# ==========================================

def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print("   [MQTT] Conectado al Broker")
        client.subscribe(TOPICO_SUSCRIBIR)
    else:
        print(f"   [MQTT] Fallo conexion: {rc}")

def on_message(client, userdata, msg):
    """
    Comandos: ABRIR, CERRAR, MANT_ON, MANT_OFF
    NUEVOS: FAN_ON, FAN_OFF, FAN_AUTO
    """
    global puerta_abierta, modo_mantenimiento, fan_modo_manual, fan_estado_manual
    orden = msg.payload.decode().upper()
    print(f"\n>> [ORDEN REMOTA] Recibido: {orden}")

    # --- CONTROL PUERTA ---
    if orden == "ABRIR":
        puerta_abierta = True
        mover_servo("ABRIR")
        registrar_evento("control_remoto", "Puerta Abierta Web")
    elif orden == "CERRAR":
        puerta_abierta = False
        mover_servo("CERRAR")
        registrar_evento("control_remoto", "Puerta Cerrada Web")

    # --- CONTROL MANTENIMIENTO ---
    elif orden == "MANT_ON":
        modo_mantenimiento = True
        registrar_evento("control_remoto", "Mantenimiento ON Web")
    elif orden == "MANT_OFF":
        modo_mantenimiento = False
        registrar_evento("control_remoto", "Mantenimiento OFF Web")

    # --- CONTROL VENTILADOR (NUEVO) ---
    elif orden == "FAN_ON":
        fan_modo_manual = True
        fan_estado_manual = True
        registrar_evento("control_remoto", "Ventilador FORZADO ENCENDIDO")
        print("   -> Fan en MODO MANUAL: ON")

    elif orden == "FAN_OFF":
        fan_modo_manual = True
        fan_estado_manual = False
        registrar_evento("control_remoto", "Ventilador FORZADO APAGADO")
        print("   -> Fan en MODO MANUAL: OFF")

    elif orden == "FAN_AUTO":
        fan_modo_manual = False
        registrar_evento("control_remoto", "Ventilador en AUTOMATICO")
        print("   -> Fan regresó a MODO AUTOMATICO")

# Iniciar MQTT
client_mqtt.on_connect = on_connect
client_mqtt.on_message = on_message
try:
    client_mqtt.connect(MQTT_BROKER, MQTT_PORT, 60)
    client_mqtt.loop_start()
except Exception as e:
    print(f"   [MQTT] Error conectando: {e}")

# ==========================================
# 6. FUNCIONES AUXILIARES
# ==========================================
def set_rgb(color):
    GPIO.output([RGB_RED, RGB_GREEN, RGB_BLUE], GPIO.LOW)
    if color == "VERDE": GPIO.output(RGB_GREEN, GPIO.HIGH)
    elif color == "ROJO": GPIO.output(RGB_RED, GPIO.HIGH)
    elif color == "AMARILLO":
        GPIO.output(RGB_RED, GPIO.HIGH)
        GPIO.output(RGB_GREEN, GPIO.HIGH)
    elif color == "AZUL": GPIO.output(RGB_BLUE, GPIO.HIGH)
    elif color == "OFF": pass

def mover_servo(estado):
    duty = 7.5 if estado == "ABRIR" else 2.5
    GPIO.output(SERVO_PIN, True)
    servo_pwm.ChangeDutyCycle(duty)
    time.sleep(0.5)
    GPIO.output(SERVO_PIN, False)
    servo_pwm.ChangeDutyCycle(0)

def lcd_print(linea1, linea2):
    if lcd:
        lcd.text(str(linea1), 1)
        lcd.text(str(linea2), 2)

def guardar_mongo_sensores(temp, hum):
    if mongo_ok:
        try:
            ahora = datetime.datetime.now()
            collection_temp.insert_one({"fecha": ahora, "valor_temperatura": float(temp), "unidad": "Celsius"})
            collection_hum.insert_one({"fecha": ahora, "valor_humedad": float(hum), "unidad": "Porcentaje"})
            print(">> [MONGO] Sensores guardados (30s)")
        except: pass

def publicar_mqtt(temp, hum, pir, puerta, mant, fan_status, fan_mode):
    """Envía estado COMPLETO a la Web (Incluyendo Fan)"""
    try:
        payload = {
            "temperatura": temp,
            "humedad": hum,
            "movimiento": int(pir),
            "puerta": "ABIERTA" if puerta else "CERRADA",
            "mantenimiento": mant,
            "ventilador": fan_status,    # ON / OFF
            "modo_ventilador": fan_mode  # AUTO / MANUAL
        }
        client_mqtt.publish(TOPICO_PUBLICAR, json.dumps(payload))
    except: pass

def registrar_evento(tipo, descripcion, valor_asociado=None):
    global ultimo_evento_tipo, tiempo_ultimo_evento
    es_alarma = "alarma" in tipo
    if es_alarma:
        if tipo == ultimo_evento_tipo and (time.time() - tiempo_ultimo_evento < 10):
            return

    if mongo_ok:
        try:
            doc = {
                "fecha": datetime.datetime.now(),
                "tipo_evento": tipo,
                "descripcion": descripcion,
                "valor_registrado": valor_asociado
            }
            collection_events.insert_one(doc)
            print(f">> [MONGO] EVENTO: {tipo} - {descripcion}")
            ultimo_evento_tipo = tipo
            tiempo_ultimo_evento = time.time()
        except: pass

# ==========================================
# 7. BUCLE PRINCIPAL
# ==========================================
lcd_print("FIUSAC DATA CNTR", "Iniciando...")
set_rgb("VERDE")
mover_servo("CERRAR")
time.sleep(2)

print("Sistema Listo. Esperando sensores...")

try:
    while True:
        # A. BOTÓN MANTENIMIENTO
        if GPIO.input(BOTON_MANT_PIN) == GPIO.LOW:
            modo_mantenimiento = not modo_mantenimiento
            estado_txt = "ACTIVO" if modo_mantenimiento else "INACTIVO"
            print(f">> BOTON: Mantenimiento {estado_txt}")
            registrar_evento("cambio_modo", f"Mantenimiento {estado_txt} (Boton)")
            time.sleep(0.5)

        # B. LÓGICA DE SENSORES
        try:
            temperature = dht_device.temperature
            humidity = dht_device.humidity
            movimiento = GPIO.input(PIR_PIN)

            if temperature is None or humidity is None:
                time.sleep(0.1)
                continue

            # --- LÓGICA DEL VENTILADOR (HÍBRIDA) ---
            fan_is_on = False

            if fan_modo_manual:
                # 1. Modo Manual: Obedece MQTT
                if fan_estado_manual:
                    GPIO.output(FAN_PIN, GPIO.HIGH)
                    fan_is_on = True
                    fan_status_txt = "ON (MANUAL)"
                else:
                    GPIO.output(FAN_PIN, GPIO.LOW)
                    fan_is_on = False
                    fan_status_txt = "OFF (MANUAL)"
            else:
                # 2. Modo Automático: Obedece Sensor
                if temperature >= TEMP_UMBRAL_FAN:
                    GPIO.output(FAN_PIN, GPIO.HIGH)
                    fan_is_on = True
                    fan_status_txt = "ON (AUTO)"
                else:
                    GPIO.output(FAN_PIN, GPIO.LOW)
                    fan_is_on = False
                    fan_status_txt = "OFF (AUTO)"

            # --- ENVÍO DE DATOS ---
            tiempo_actual = time.time()

            if tiempo_actual - tiempo_ultimo_log_mongo >= INTERVALO_MONGO:
                guardar_mongo_sensores(temperature, humidity)
                tiempo_ultimo_log_mongo = tiempo_actual

            if tiempo_actual - tiempo_ultimo_mqtt >= INTERVALO_MQTT:
                # Enviamos también el estado del ventilador
                mode_txt = "MANUAL" if fan_modo_manual else "AUTO"
                status_simple = "ON" if fan_is_on else "OFF"
                publicar_mqtt(temperature, humidity, movimiento, puerta_abierta, modo_mantenimiento, status_simple, mode_txt)
                tiempo_ultimo_mqtt = tiempo_actual

            # --- MODO MANTENIMIENTO ACTIVO ---
            if modo_mantenimiento:
                lcd_print("MODO MANTENIMIEN", "ACTIVO")
                set_rgb("AMARILLO")
                # En mantenimiento forzamos apagado de actuadores ruidosos
                GPIO.output(FAN_PIN, GPIO.LOW)
                GPIO.output(BUZZER_PIN, GPIO.LOW)
                time.sleep(0.5)
                set_rgb("OFF")
                time.sleep(0.5)
                continue

            # --- MODO NORMAL (ALARMAS) ---
            print(f"T:{temperature}C H:{humidity}% PIR:{movimiento} FAN:{fan_status_txt}")

            # Alarma Intrusión
            if movimiento and not puerta_abierta:
                print(">> ALERTA: INTRUSION")
                lcd_print("! INTRUSION !", "DETECTADA")
                registrar_evento("alarma_intrusion", "Movimiento detectado")
                for _ in range(3):
                    set_rgb("ROJO")
                    GPIO.output(BUZZER_PIN, GPIO.HIGH)
                    time.sleep(0.1)
                    set_rgb("AZUL")
                    GPIO.output(BUZZER_PIN, GPIO.LOW)
                    time.sleep(0.1)
                GPIO.output(LEDS_BLANCOS_PIN, GPIO.HIGH)

            # Alarma Temperatura (Solo visual/sonora, el fan ya se manejó arriba)
            elif temperature >= TEMP_UMBRAL_ALERTA:
                lcd_print("! TEMP CRITICA !", f"{temperature}C")
                registrar_evento("alarma_temperatura", "Temp Critica", temperature)
                set_rgb("ROJO")
                GPIO.output(BUZZER_PIN, GPIO.HIGH)

            # Alarma Humedad
            elif humidity >= HUM_UMBRAL_ALERTA:
                lcd_print("! HUMEDAD ALTA !", f"{humidity}%")
                registrar_evento("alarma_humedad", "Humedad Alta", humidity)
                set_rgb("AMARILLO")
                GPIO.output(BUZZER_PIN, GPIO.HIGH)
                time.sleep(0.2)
                GPIO.output(BUZZER_PIN, GPIO.LOW)

            # Estado Normal
            else:
                set_rgb("VERDE")
                GPIO.output(BUZZER_PIN, GPIO.LOW)
                GPIO.output(LEDS_BLANCOS_PIN, GPIO.LOW)
                estado_puerta_txt = "ABIERTA" if puerta_abierta else "CERRADA"
                # Mostrar estado del ventilador en LCD para debug visual
                fan_lcd = "ON" if fan_is_on else "OFF"
                lcd_print(f"T:{temperature}C H:{humidity}%", f"F:{fan_lcd} P:{estado_puerta_txt}")

            time.sleep(0.5)

        except RuntimeError:
            continue

except KeyboardInterrupt:
    print("\nApagando sistema...")
    client_mqtt.loop_stop()
    GPIO.cleanup()
    if lcd: lcd.clear()