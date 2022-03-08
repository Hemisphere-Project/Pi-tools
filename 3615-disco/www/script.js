$(document).ready(function() {

    var me = ""

    function Service(info, parent) {
        this.info = info
        this.parent = parent

        serviceShort = info.service_name.split(' ').slice(0, 2).join(' ')

        target = ""
        hosturl = info.host.toLowerCase() + ".local"

        console.log(hosturl, window.location.hostname)

        // HTTP service
        if (info.type.startsWith("_http")) {
            if (serviceShort == "3615") target = "_self" // 3615 : go to own page
            else if (serviceShort == "Regie") target = "_blank" // Regie: easier in own page
            else if (serviceShort == "SyncZinc") target = "_blank" // Syncthing do not accept CORS
            else if (hosturl == window.location.hostname) target = "mainframe" // If device selected => iframe
            else target = "_blank"
        }

        // clickable badge
        if (target) {
            protocol = 'http://'
            if (info.port == 8443) protocol = 'https://'
            this.badge = $('<a/>', {
                    href: protocol + hosturl + ":" + info.port,
                    text: serviceShort,
                    class: "badge badge-pill mr-1",
                    target: target
                }).appendTo(parent)
                .on('click', (e) => {
                    e.stopPropagation()
                })

            if (target == "_blank") this.badge.addClass("badge-warning");
            else this.badge.addClass("badge-success");
        }

        // not clickable
        else {
            this.badge = $('<span/>', {
                text: serviceShort,
                class: "badge badge-secondary badge-pill mr-1"
            });
            this.badge.appendTo(parent)
        }
    }

    function Device(name, info) {
        var that = this;
        this.name = name
        this.host = name.toLowerCase() + ".local"
        this.services = []

        this.button = $('<li/>', { class: "list-group-item list-group-item-action py-2 px-2 mb-1" });
        this.button.append('<h5 class="mb-1">' + name + '</h5>')

        this.badges = $('<p/>', { class: "mb-1" });
        this.badges.appendTo(this.button)

        this.button.append('<small>' + info.ip.join(' - ') + '</small>')
        this.button.appendTo('#devices')

        this.button.on('click', () => {
            location.assign('http://' + that.host);
        })

        console.log(this.name, me)

        if (this.name == me)
            this.button.addClass('active')

        var isMaster = false
        for (const i of info.ip)
            if (i == window.location.hostname) isMaster = true;
        if (!isMaster) this.button.addClass("list-group-item-secondary")

        this.addService = function(service) {
            this.services.push(new Service(service, this.badges))
            console.log("add service", service)
        }

        this.removeService = function(name) {
            for (var i in this.services)
                if (this.services[i].info.fullname == name) {
                    this.services[i].badge.remove()
                    this.services.splice(i, 1);
                    console.log("remove service", name)
                }
        }

        // Add badges
        Object.keys(info.services).sort().forEach(function(servname) {
            that.addService(info.services[servname])
        });
    }

    var devices = []

    function getDevice(hostname) {
        for (var d of devices)
            if (d.name == hostname) return d;
        return Device("dummy")
    }


    var socket = io.connect(location.protocol + '//' + document.domain + ':' + location.port);
    var last_status;
    var last_status_str;

    function setBtnClass(sel, style, active) {
        if (active) {
            $(sel).addClass('btn-' + style)
            $(sel).removeClass('btn-outlined-' + style)
        } else {
            $(sel).removeClass('btn-' + style)
            $(sel).addClass('btn-outlined-' + style)
        }
    }

    /*
      SOCKETIO
    */

    socket.on('connect', function() {
        console.log('SocketIO connected :)')
        $('#link-connected').show();
        $('#link-disconnected').hide();
    });

    socket.on('disconnect', function() {
        console.log('SocketIO disconnected :(')
        $('#link-connected').hide();
        $('#link-disconnected').show();
    });

    socket.on('name', function(name) {
        console.log('Device name:', name)
        $('#deviceName').html(name);
        me = name
    });

    socket.on('init', (state) => {
        state = JSON.parse(state)
        console.log('init:', state)

        $("#devices").empty()
        for (var host in state) {
            var dev = new Device(host, state[host])
            devices.push(dev)
        }
    })

    socket.on('device-new', (state) => {
        state = JSON.parse(state)
        console.log('device-new:', state)

        var dev = new Device(state['host'], state)
        devices.push(dev)
    })

    socket.on('service-add', (state) => {
        state = JSON.parse(state)
        console.log('service-add:', state)
        getDevice(state['host']).addService(state['service'])
    })

    socket.on('service-remove', (state) => {
        state = JSON.parse(state)
        console.log('service-remove:', state)
        getDevice(state['host']).removeService(state['service'])
    })

    socket.on('status', function(msg) {
        console.log('status:', msg)
    });

});