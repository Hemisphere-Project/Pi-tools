
import socketio
from flask import Flask, render_template, session, request, send_from_directory
from flask_socketio import SocketIO, emit, join_room, leave_room, close_room, rooms, disconnect
import threading, os, time, socket
from eventemitter import EventEmitter
from zeroconf import ServiceInfo, Zeroconf
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
