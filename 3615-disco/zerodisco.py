import socket
import json
from typing import cast
from eventemitter import EventEmitter
from zeroconf import ServiceBrowser, ServiceStateChange, Zeroconf

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