import sys
from zeroconf import ServiceInfo, Zeroconf, ServiceBrowser, ServiceStateChange
import inspect

class EventEmitter:
    def __init__(self, log=False):
        self._eventshandlers = {}
        self._doLog = log

    def trigger(self, eventname, args=None):
        if self._doLog:
            print("event:", eventname, "/ args:", args)

        if '*' in self._eventshandlers:
            for clbk in self._eventshandlers['*']:
                clbk(eventname, args)

        if eventname in self._eventshandlers:
            for clbk in self._eventshandlers[eventname]:
                if len(inspect.getfullargspec(clbk).args) > 0: 
                    clbk(args)
                else: 
                    clbk()

    def on(self, eventname, handler=None):
        if not type(eventname) is list:
                eventname = [eventname]
        def registerhandler(handler):
            for e in eventname:
                if e in self._eventshandlers:
                    self._eventshandlers[e].append(handler)
                else:
                    self._eventshandlers[e] = [handler]
            return handler
        if handler: registerhandler(handler)    # direct call object.on("event", do)
        else: return registerhandler            # decorator call @object.on("event")

import socketio
from flask import Flask, render_template, session, request, send_from_directory
from flask_socketio import SocketIO, emit, join_room, leave_room, close_room, rooms, disconnect
import threading, os, time, socket
import socket
import netifaces as ni
import eventlet
eventlet.monkey_patch()



#
# Utils
#
def get_allip():
    ip = []
    ifaces = ni.interfaces()
    for iface in ifaces:
        if iface.startswith("e") or iface.startswith("w"):
            try:
                ip.append(ni.ifaddresses(iface)[socket.AF_INET][0]['addr'])
            except:
                pass
    return ip


#
# Threaded Flask Server
#
class FlaskServer(EventEmitter):
    
    def __init__(self, port):
        super().__init__()
        self.port = port

        this_path = os.path.dirname(os.path.realpath(__file__))
        www_path = os.path.join(this_path, 'www')

        app = Flask(__name__, template_folder=www_path)
        app.config['SECRET_KEY'] = 'secret!'
        socketio = SocketIO(app, async_mode='eventlet') 
        self.socketio = socketio

        #
        #  SOCKETio refresh status
        #
        def refresh_fn():
            while True: 
                socketio.emit('status', 'yo rasta')              
                socketio.sleep(2)

        socketio.start_background_task(target=refresh_fn)

        #
        # FLASK Routing
        #
        @app.route('/')
        def index():
            self.trigger('index')
            return send_from_directory(www_path, 'index.html')
        
        @app.route('/<path:path>') 
        def static_route(path):
            return send_from_directory(www_path, path)


        #
        # SOCKETIO Routing
        #
        
        self.sendSettings = None
        self.sendPlaylist = None


        @socketio.on('connect')
        def client_connect():
            print('connect' )
            self.trigger('connect')
            socketio.emit('name', socket.gethostname())
            print('name', socket.gethostname() )

        @socketio.on('disconnect')
        def client_disconnect():
            self.trigger('disconnect')
            print("Client disconnected")
            pass

        # prepare sub-thread
        self.server_thread = threading.Thread(target=lambda:socketio.run(app, host='0.0.0.0', port=port))
        self.server_thread.daemon = True


    def start(self):
        self.server_thread.start()
        print("Web server started on port", self.port)
        self.zeroconf = Zeroconf()
        hostname = socket.gethostname()
        self.info = ServiceInfo(
            "_http._tcp.local.",
            "3615._"+hostname+"._http._tcp.local.",
            addresses=[socket.inet_aton(ip) for ip in get_allip()],
            port=self.port,
            properties={},
            server=hostname+".local.",
        )
        self.zeroconf.register_service(self.info)

    def stop(self):
        self.zeroconf.unregister_service(self.info)
        self.zeroconf.close()
        print("Web server stopped")
    
    # with in
    def __enter__(self):                
        self.start()
        return self

    # with out
    def __exit__(self, type, value, traceback):
        self.stop()


import socket
import json
from typing import cast

def dumper(obj):
    return obj.__dict__

zeroconf = Zeroconf()


class ZeroService():
    def __init__(self, fullname, type):
        self.fullname = fullname
        self.service_name = fullname.replace(type, '').split('.')[0]
        self.service_host = fullname.replace(type, '').split('.')[1][1:]
        self.type = type
        
        info = zeroconf.get_service_info(type, fullname)   # contains: weight, priority, server, properties 
        if info:
            self.addresses = ["%s:%d" % (socket.inet_ntoa(addr), cast(int, info.port)) for addr in info.addresses]
            self.host = info.server.split('.')[0]
            self.ip = [socket.inet_ntoa(ip) for ip in info.addresses]
            self.port = cast(int, info.port)
            self.validDevice = True
            self.validConfig = True
        else:
            self.validDevice = False
            self.validConfig = False


class ZeroDevice():
    def __init__(self, ip, host):
        self.ip = [ip]
        self.host = host
        self.services = {}

    def add(self, service):
        service.validDevice = (service.ip in self.ip) and (self.host == service.host) # and (self.host == service.service_host)
        self.services[service.fullname] = service
        return service

    def export(self):
        return json.dumps(self, default=dumper)


class ZeroDisco(EventEmitter):

    def __init__(self):
        super().__init__()
        self.browsers = {}
        self.devices = {}

    def stop(self):  
        zeroconf.close()

    def add(self, type, protocol="tcp"):
        typepath = "_"+type+"._"+protocol+".local."
        if not typepath in self.browsers:
            self.browsers[typepath] = ServiceBrowser(zeroconf, typepath, handlers=[self.on_service_state_change]) 

    def export(self):
        return json.dumps(self.devices, default=dumper)


    def on_service_state_change(self, zeroconf: Zeroconf, service_type: str, name: str, state_change: ServiceStateChange) -> None:
        if state_change is ServiceStateChange.Added:
            self.serviceAdd(name, service_type)
        elif state_change is ServiceStateChange.Removed:
            self.serviceRemove(name, service_type)
        elif state_change is ServiceStateChange.Updated:
            self.serviceUpdate(name, service_type)


    def serviceAdd(self, name, service_type):
        print("ADD %s of type %s" % (name, service_type))
        service = ZeroService(name, service_type)

        if service.validConfig:
            # create device if new
            if not service.host in self.devices:
                self.devices[service.host] = ZeroDevice(service.ip, service.host)
                self.trigger('device-new', self.devices[service.host].export())
            
            # check if new ip detected
            if not service.ip in self.devices[service.host].ip:
                self.devices[service.host].ip.append(service.ip)

            # remove service if already present
            if service.fullname in self.devices[service.host].services:
                del self.devices[service.host].services[service.fullname]
                self.trigger('service-remove', json.dumps({'host':service.host, 'service': service.fullname}))

            # add service
            newserv = self.devices[service.host].add(service)
            self.trigger('service-add', json.dumps({'host':service.host, 'service': newserv}, default=dumper))

            

    def serviceRemove(self, name, service_type):
        print("REMOVE %s of type %s" % (name, service_type))
        for host in self.devices:
            if name in self.devices[host].services:
                del self.devices[host].services[name]
                self.trigger('service-remove', json.dumps({'host':host, 'service': name}))


    def serviceUpdate(self, name, service_type):
        print("UPDATE %s of type %s" % (name, service_type))
        self.serviceRemove(name, service_type)
        self.serviceAdd(name, service_type)


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
