
# EXECUTE this on the main introducer

# TODO:
# catch requests errors and add retry (instead of time.sleep)

from syncthing import Syncthing
from xml.dom import minidom
import sys, time
import os.path
import requests
import subprocess, traceback

# Basepath
basepath = os.path.dirname(os.path.realpath(__file__))

# Start local client
syncClient = subprocess.Popen([ os.path.join( basepath, 'peer.sh'), 'master' ])
time.sleep(6)

# get common API key
with open(os.path.join( basepath, 'key'), 'r') as theFile:
    apikey = theFile.read()

# get API key form config.xml
confpath = '/data/var/syncthing/config.xml'
if not os.path.exists(confpath):
    print('Can\'t find config file',confpath)
    syncClient.terminate()
    exit(1)
mydoc = minidom.parse(confpath)
localkey = mydoc.getElementsByTagName('apikey')[0].firstChild.nodeValue


# REST connect
def connect(ip):
    
    retry = 0
    retryMax = 10
    
    # start local link
    m = Syncthing(apikey, host=ip, timeout=20.0)
    
    # Check connection
    while True:
        try:
            m.system.connections()
            break
        except:
            retry += 1
            if retry > retryMax: 
                print("\tCan't connect to ", ip, "abort. ")
                return None
            time.sleep(2.0)
            print("\tCan't connect to ", ip, "retrying... ",retry, "/", retryMax)



    # check for errors
    if m.system.errors():
        for e in m.system.errors():
            print('[synczinc] CONNECT ERROR', e)
            
    m.system.clear()

    return m

# LOCAL connect
LOCAL = connect('127.0.0.1')

# SERVER configuration
# compare Common key and Local key => if different, server must be reconfigured !
if localkey != apikey:
    print("This device was not configured as a Zinc Server.. ")
    print("Configuring now.")

    subprocess.run(["mkdir", "-p", "/data/sync"])

    config = LOCAL.system.config()

    # SYNC folder
    config['folders'] = [{
        'id': 'sync',
        'label': 'sync',
        'filesystemType': 'basic',
        'path': '/data/sync',
        'type': 'sendonly',
        # 'devices': [{ 'deviceID': LOCAL.system.status()['myID'], 'introducedBy': '' }],
        'rescanIntervalS': 3600, 'fsWatcherEnabled': True, 'fsWatcherDelayS': 5, 'ignorePerms': False, 'autoNormalize': True, 'minDiskFree': { 'value': 5, 'unit': '%' }, 'versioning': { 'type': '', 'params': {} }, 
        'copiers': 0, 'pullerMaxPendingKiB': 0, 'hashers': 0, 'order': 'random', 'ignoreDelete': False, 'scanProgressIntervalS': 0, 'pullerPauseS': 0, 'maxConflicts': -1, 'disableSparseFiles': False, 'disableTempIndexes': False, 'paused': False, 'weakHashThresholdPct': 25, 'markerName': '.stfolder', 'useLargeBlocks': True, 'copyOwnershipFromParent': False
    }]

    # DEVICES me only
    # me = None
    # for dev in config['devices']:
    #     if dev['deviceID'] == LOCAL.system.status()['myID']:
    #         me = dev
    # config['devices'] = [me] if me else []
    config['devices'] = []

    # GUI
    config['gui']['address'] = '0.0.0.0:8384'
    config['gui']['apiKey'] = apikey
    config['gui']['insecureAdminAccess'] = True
    config['gui']['theme'] = 'dark'

    # OPTIONS
    config['options']['globalAnnounceEnabled'] = False
    config['options']['relaysEnabled'] = False
    config['options']['startBrowser'] = False
    config['options']['natEnabled'] = False
    config['options']['urAccepted'] = -1
    config['options']['overwriteRemoteDeviceNamesOnConnect'] = True
    config['options']['defaultFolderPath'] = '/data' # OLD VERSION
    config['options']['crashReportingEnabled'] = False
    
    # New version
    if 'defaults' in config:
        config['defaults']['folder']['path'] = '/data'

    print("Applying Server conf.")
    try:
        LOCAL.system.set_config(config)
        LOCAL.system.restart()
    except:
        pass
    LOCAL = connect('127.0.0.1')

else:
    print("This machine is properly configured as a local Sync server")


# REMOTE client configuration
def autoconfremote(ip):

    # remote link
    print("\tDevice", ip, " connecting..")
    r = connect(ip)
    if not r:
        print("\tDevice", ip, " unreachable..")
        return
    print("\tDevice", ip, " connected..")

    # get remote config
    print("\tDevice", ip, " get remote config..")
    rconfig = r.system.config()
    configUpdated = False

    print("\n BEFORE")
    # print(rconfig)

    # Fresh install
    if rconfig['gui']['apiKey'] != apikey:
        
        # remove default folders
        del rconfig['folders'] 
        
        # customize options
        rconfig['options']['globalAnnounceEnabled'] = False
        rconfig['options']['relaysEnabled'] = False
        rconfig['options']['startBrowser'] = False
        rconfig['options']['natEnabled'] = False
        rconfig['options']['urAccepted'] = -1
        rconfig['options']['overwriteRemoteDeviceNamesOnConnect'] = True
        rconfig['options']['defaultFolderPath'] = '/data'   # OLD VERSION
        rconfig['options']['crashReportingEnabled'] = False
        if 'defaults' in rconfig:
            rconfig['defaults']['folder']['path'] = '/data'
        
        # fix access (or restart will loose it)
        rconfig['gui']['address'] = '0.0.0.0:8384'
        rconfig['gui']['apiKey'] = apikey
        rconfig['gui']['insecureAdminAccess'] = True
        
        configUpdated = True
        print("\tDevice", ip, " Fresh device detected ",event['data']['device'])
    
    
    # Not introduced by this master
    if not LOCAL.system.status()['myID'] in [d['deviceID'] for d in rconfig['devices'] if d['introducer']]:
        introducer = {}
        introducer['deviceID']       = LOCAL.system.status()['myID']
        introducer['name']           = 'Introducer'
        introducer['addresses']      = ['dynamic']
        introducer['compression']    = 'metadata'
        introducer['certName']       = ''
        introducer['introducer']     = True
        introducer['autoAcceptFolders'] = True
        rconfig['devices'].append(introducer)
        
        configUpdated = True
        print("\tDevice", ip, " Adding self as introducer ",event['data']['device'])
        

    if configUpdated:
        r.system.set_config(rconfig)
        time.sleep(5)
        r.system.reset()
        configUpdated = False        
        print("\tDevice", ip, " Config applied ")
    else:    
        print("\tDevice", ip, " already configured, with introducers: ", [d['deviceID'] for d in rconfig['devices'] if d['introducer']])       



#
# RUN
#
# watch for new node !
lastEventId = None
while True:
    try:
        event_stream = LOCAL.events(last_seen_id=lastEventId)
        for event in event_stream:
            # print("event", event)
            lastEventId = event['id']
            
            # log events
            if event['type'].startswith('Device') and 'device' in event['data']:
                print(event['type'], event['data']['device'])
            else:
                print(event['type'])

            #
            # Check if remote device is properly set up
            #
            if event['type'] == 'DeviceDiscovered':

                # detect devic ip4
                ip = None
                for addr in event['data']['addrs']:
                    adip = addr.split('tcp://')
                    if len(adip) == 2 and adip[1][0].isdigit():
                        ip = adip[1].split(':')[0]
                        break
                
                if ip:
                    print("[synczinc] Device discovered: checking remote config", ip)
                    autoconfremote(ip)


            #
            # Register unknown remote device 
            #
            elif event['type'] == 'DeviceRejected':
                print("[synczinc] Device rejected: adding to local pool")

                config = LOCAL.system.config()

                newDevice = {}
                newDevice['deviceID']       = event['data']['device']
                newDevice['name']           = event['data']['name']
                newDevice['addresses']      = ['dynamic']
                newDevice['compression']    = 'metadata'
                newDevice['certName']       = ''
                newDevice['introducer']     = False
                config['devices'].append(newDevice)
                print('[synczinc] Add new device:', event['data']['device'], event['data']['name'])
                
                # auto share folders
                for f in config['folders']:
                    addMe = True
                    for d in f['devices']:
                        if d['deviceID'] == event['data']['device']:
                            addMe = False
                            break
                    if addMe:
                        f['devices'].append({'deviceID':event['data']['device']})
                        print('[synczinc] Share folder', f['label'], 'with', event['data']['name'])
                        
                LOCAL.system.set_config(config)
                
    except requests.exceptions.ConnectionError as e:
        print('requests end')

    except Exception as e:
        if str(e): raise(e)     #ignore empty Exception (mostly connections timeouts)
                
    
