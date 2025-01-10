from flask import Flask, request
from smd.red import *
from serial.tools.list_ports import comports
from platform import system
import threading
import time

app = Flask(__name__)
class PIDController:
    def __init__(self, kp, ki, kd):
        self.kp = kp
        self.ki = ki
        self.kd = kd
        self.previous_error = 0
        self.integral = 0

    def calculate(self, error, delta_time):
        self.integral += error * delta_time
        derivative = (error - self.previous_error) / delta_time if delta_time > 0 else 0
        output = (self.kp * error) + (self.ki * self.integral) + (self.kd * derivative)
        self.previous_error = error
        return max(min(output, 100), -100)  # Clamp output to motor speed range
# Robot Setup
def USB_Port():
    ports = list(comports())
    usb_names = {
        "Windows": ["USB Serial Port"],
        "Linux": ["/dev/ttyUSB"],
        "Darwin": [
            "/dev/tty.usbserial",
            "/dev/tty.usbmodem",
            "/dev/tty.SLAB_USBtoUART",
            "/dev/tty.wchusbserial",
            "/dev/cu.usbserial",
            "/dev/cu.usbmodem",
            "/dev/cu.SLAB_USBtoUART",
            "/dev/cu.wchusbserial",
        ],
    }
    os_name = system()
    if ports:
        for port, desc, hwid in sorted(ports):
            if any(name in port or name in desc for name in usb_names.get(os_name, [])):
                return port
        print("Current ports:")
        for port, desc, hwid in ports:
            print(f"Port: {port}, Description: {desc}, Hardware ID: {hwid}")
    else:
        print("No port found")
    return None

port = USB_Port()
smd = Master(port) if port else None
if smd:
    smd.attach(Red(0))  # Left motor
    smd.attach(Red(1))  # Right motor
    smd.set_operation_mode(0, OperationMode.PWM)
    smd.set_operation_mode(1, OperationMode.PWM)
    smd.set_shaft_rpm(0, 100)
    smd.set_shaft_rpm(1, 100)
    smd.set_shaft_cpr(0, 6533)
    smd.set_shaft_cpr(1, 6533)
    smd.enable_torque(0, 1)
    smd.enable_torque(1, 1)
    left_pid = PIDController(kp=23.55, ki=0.00, kd=18.65)
    right_pid = PIDController(kp=21.37, ki=0.00, kd=18.15)
    base_speed = 60 
    turning_speed = 40
def stop_robot():
    """Stop the robot by setting duty cycle to 0."""
    smd.set_duty_cycle(0, 0)
    smd.set_duty_cycle(1, 0)

def watchdog_check():
    """Check periodically if the motors are stuck or not working."""
    while True:
        # Logic to check if motors are stuck (e.g., if duty cycle hasn't changed for a while)
        # You can implement a simple check based on time or position feedback.
        # For now, we just print a simple message.
        print("Watchdog: Checking motor status.")
        time.sleep(5)  # Periodically check every 5 seconds

# Start a separate thread for watchdog monitoring
watchdog_thread = threading.Thread(target=watchdog_check, daemon=True)
watchdog_thread.start()

@app.route('/control', methods=['POST'])
def control():
    global last_command_time
    data = request.get_json()
    direction = data.get('direction', '')
    target_speed = 60  # Hedef hız
    turning_speed = 40  # Dönüş sırasında kullanılacak hız
    left_speed = 0
    right_speed = 0

    if smd:
        last_command_time = time.time()  
        current_time = time.time()
        delta_time = current_time - last_command_time

        if direction == '1':  # Move forward
            error = target_speed
            left_speed = left_pid.calculate(error, delta_time)
            right_speed = right_pid.calculate(error, delta_time)
            smd.set_duty_cycle(0, -left_speed)  # Left motor forward
            smd.set_duty_cycle(1, right_speed)
        elif direction == '4':  # Move backward
            error = -target_speed
            left_speed = left_pid.calculate(error, delta_time)
            right_speed = right_pid.calculate(error, delta_time)
            smd.set_duty_cycle(0, -left_speed)  # Left motor backward
            smd.set_duty_cycle(1, right_speed)  # Right motor backward
        elif direction == '3':  # Turn right
           smd.set_duty_cycle(0, -turning_speed)  # Left motor forward
           smd.set_duty_cycle(1, 0)

        elif direction == '2':  # Turn left
           smd.set_duty_cycle(0, 0)  
           smd.set_duty_cycle(1, turning_speed)

        elif direction == '0':  # Stop
            stop_robot()
            return {"status": "success", "direction": direction}


    return {"status": "error", "message": "Robot not connected"}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5005, debug=True)

