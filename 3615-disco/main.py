import sys
from zeroconf import ServiceInfo, Zeroconf 
from eventemitter import EventEmitter
from flaskserver import FlaskServer
from zerodisco import ZeroDisco

config = { "port": 80 }

# RUN flag
import signal, sys, threading
run = threading.Lock()
run.acquire()

# CTRL-C handler
def ctrlC(signal, frame):
    run.release()
signal.signal(signal.SIGINT, ctrlC)

# START SERVER
flask = FlaskServer(config['port'])
flask.start()

# START DISCO
zero  = ZeroDisco()

@zero.on('*')
def forward_event(event, data):
    flask.socketio.emit(event, data)

@flask.on('connect')
def newgui():
    flask.socketio.emit('init', zero.export())


zero.add("dummy")
zero.add("http")
zero.add("http-api")
zero.add("mqtt")
zero.add("mqttc")
zero.add("apple-midi", "udp")
zero.add("osc", "udp")

# WAIT for CTRL-C
run.acquire()

zero.stop()
flask.stop()

print("Goodbye !")
