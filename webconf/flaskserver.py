
from flask import Flask, render_template, session, request, send_from_directory
from flask_socketio import SocketIO, emit, join_room, leave_room, close_room, rooms, disconnect
import threading, os, time, socket
from zeroconf import ServiceInfo, Zeroconf
import socket
import netifaces as ni
import eventlet, os, fileinput, sys, copy
eventlet.monkey_patch()


#
# Utils
#
def get_allip():
    ip = []
    ifaces = ni.interfaces()
    for iface in ifaces:
        if iface.startswith("e") or iface.startswith("w"):
            ip.append(ni.ifaddresses(iface)[socket.AF_INET][0]['addr'])
    return ip


def getline(string, file):
    try:
        with open(file, "r") as fp:
            for line in fp:
                if string in line:
                    return line
    except:
        pass
    return ''


def replaceline(find, replace, file):
    try:
        for line in fileinput.input(file, inplace=1):
            if find in line:
                comment = line.split('#')[-1].strip() if len(line.split('#')) > 1 else ''
                line = replace
                if comment: 
                    line += ' # '+comment
                line+='\n'
            sys.stdout.write(line)
    except:
        pass


def commentline(find, file):
    try:
        for line in fileinput.input(file, inplace=1):
            if find in line:
                if not line.strip().startswith('#'):
                    line = '# '+line.strip()+'\n'
    except:
        pass

    
def uncommentline(find, file):
    try:
        for line in fileinput.input(file, inplace=1):
            if find in line:
                if line.startswith('#'):
                    line = line[1:].strip()+'\n'
    except:
        pass

#
# Threaded Flask Server
#
class FlaskServer():

    def refresh(self):
        self._settings = {}
        
        self._settings['hostname'] = {
                'label':    'Hostname',
                'field':    'text|15',
                'legend':   '',
                'value':    getline('hostrename@', '/boot/starter.txt').split('@')[-1].split('#')[0].strip(),
                'apply':    lambda value: replaceline('hostrename@', 'hostrename@'+value.strip(), '/boot/starter.txt') if value.strip() != '' else False
            }
        
        if os.path.isfile('/boot/wifi/wlan0-hotspot.nmconnection'):
            self._settings['hostname']['label'] = 'Hotspot'
            self._settings['wifipass'] = {
                    'label':    'Hotspot password',
                    'field':    'text|15',
                    'legend':   '8 char. minimum',
                    'value':     getline('psk=', '/boot/wifi/wlan0-hotspot.nmconnection').split('=')[-1].split('#')[0].strip(),
                    'apply':     lambda value: replaceline('psk=', 'psk='+value.strip(), '/boot/wifi/wlan0-hotspot.nmconnection') if len(value.strip()) >= 8 else False
                }

        if os.path.isfile('/boot/wifi/wlan0-hotspot.nmconnection') or getline('wlan0-off@', '/boot/starter.txt')[0] != '#':
            self._settings['wlan-off'] = {
                    'label':    'Wifi OFF',
                    'field':    'text|15',
                    'legend':   'seconds (0 to disable WIFI-OFF)',
                    'value':     getline('wlan0-off@', '/boot/starter.txt').split('@')[-1].split('#')[0].strip() if getline('wlan0-off@', '/boot/starter.txt')[0] != '#' else '0',
                    'apply':     lambda value: replaceline('wlan0-off@', 'wlan0-off@'+str(int(value)), '/boot/starter.txt') if int(value) > 0 else replaceline('wlan0-off@', '# wlan0-off@'+str(int(value)), '/boot/starter.txt')
                }

        self._settings['hdmi'] = {
                'label':    'HDMI mode',
                'field':    'text|15',
                'legend':   '82: 1080p / 85: 720p / 16: 1024x768 / 51: 1600x1200 / 9: 800x600',
                'value':     getline('hdmi_mode=', '/boot/config.txt').split('=')[-1].split('#')[0].strip(),
                'apply':     lambda value: replaceline('hdmi_mode=', 'hdmi_mode='+str(int(value)), '/boot/config.txt') if int(value) > 0 else False
            }
        
        # for line in fileinput.input('/boot/starter.txt'):
        #     if not line.startswith('#'):
        #         self._settings[line.split('@')[0].strip()] = {
        #             'label':    'HDMI mode',
        #             'field':    'text|15',
        #             'legend':   '82: 1080p / 85: 720p / 16: 1024x768 / 51: 1600x1200 / 9: 800x600',
        #             'value':     getline('hdmi_mode=', '/boot/config.txt').split('=')[-1].split('#')[0].strip(),
        #             'apply':     lambda value: replaceline('hdmi_mode=', 'hdmi_mode='+str(int(value)), '/boot/config.txt') if int(value) > 0 else False
        #         }



    def settings(self):
        sets = copy.deepcopy(self._settings)
        for k in sets:
            sets[k]['apply'] = None
        return sets

    def __init__(self, port):
        super().__init__()
        self.port = port

        self.refresh()

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
            return send_from_directory(www_path, 'index.html')
        
        @app.route('/<path:path>') 
        def static_route(path):
            return send_from_directory(www_path, path)


        #
        # SOCKETIO Routing
        #
        
        self.sendSettings = None
        self.sendPlaylist = None

        @socketio.on('refresh')
        @socketio.on('connect')
        def client_connect():
            socketio.emit('name', socket.gethostname())
            socketio.emit('settings', self.settings())

        @socketio.on('disconnect')
        def client_disconnect():
            print("Client disconnected")
            pass

        @socketio.on('update')
        def update_values(values):
            os.system('rw')
            for (key, value) in values.items():
                if key in self._settings:
                    self._settings[key]['apply'](value)
            os.system('sync')
            os.system('ro')
            self.refresh()
            socketio.emit('settings', self.settings())
            print('updated: ', values)
            if 'reboot' in values and values['reboot']:
                os.system('reboot')

        # prepare sub-thread
        self.server_thread = threading.Thread(target=lambda:socketio.run(app, host='0.0.0.0', port=port))
        self.server_thread.daemon = True


    def start(self):
        self.server_thread.start()
        print("Web server started on port", self.port)
        self.zeroconf = Zeroconf()
        self.info = ServiceInfo(
            "_http._tcp.local.",
            "webconf._"+socket.gethostname()+"._http._tcp.local.",
            addresses=[socket.inet_aton(ip) for ip in get_allip()],
            port=self.port,
            properties={},
            server=socket.gethostname()+".local.",
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


    