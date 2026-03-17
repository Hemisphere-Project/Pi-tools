$(document).ready(function() {

    const interestingType = ['http', 'https', 'osc', 'mqtt', 'mqttc', 'smb', 'http-api', 'apple-midi']
    var showNotInteresting = false

    var me = ""

    function Service(info, parent) {
        this.info = info
        this.parent = parent

        if (this.info.type.startsWith("http") || this.info.protocol.startsWith("http")) {
            serviceShort = info.name
            if (serviceShort == this.info.host.split('.')[0]) 
                serviceShort = "WebUI ("+this.info.port+")"
        }
        else serviceShort = this.info.type+'://'

        target = ""
        hosturl = info.host.toLowerCase()

        // HTTP service
        if (info.type.startsWith("http") || this.info.protocol.startsWith("http")) {
            if (serviceShort == "3615") target = "_self"
            else if (serviceShort == "Regie") target = "_blank"
            else if (serviceShort == "SyncZinc") target = "_blank"
            else if (hosturl == window.location.hostname) target = "mainframe"
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

            if (target == "_blank") this.badge.addClass("badge-warning");
            else this.badge.addClass("badge-success");
        }

        // copy on click
        else {
            this.badge = $('<span/>', {
                text: serviceShort,
                class: "badge badge-secondary badge-pill mr-1"
            }).appendTo(parent)
        }
    }

    function Device(info) {
        this.info = info
        this.name = info.host.split('.')[0]
        this.ip = []
        this.services = []
        this.interesting = false

        this.button = $('<li/>', { class: "list-group-item list-group-item-action py-2 px-2 mb-1" });
        $('<h5 class="title mb-1">' + this.name + '</h5>').appendTo(this.button)

        this.badges = $('<p/>', { class: "mb-1" });
        this.badges.appendTo(this.button)

        this.button.appendTo('#devices')

        if (this.name == me) this.button.addClass('active')

        this.addService = function(service) {  
            for (var s of this.services)
                if (s.info.fqdn == service.fqdn) return
            this.services.push(new Service(service, this.badges))
            if (interestingType.includes(service.type)) this.interesting = true
            if (interestingType.includes(service.protocol)) this.interesting = true
            
            if (this.interesting) this.button.addClass("interesting")
            else this.button.addClass("not-interesting")
        }

        this.removeService = function(name) {
            for (var i in this.services)
                if (this.services[i].info.fullname == name) {
                    this.services[i].badge.remove()
                    this.services.splice(i, 1);
                }
        }

        this.addIP = function(ip) {
            if (!Array.isArray(ip)) ip = [ip]
            for (var i in ip) {
                if (this.ip.includes(ip[i])) return
                this.ip.push(ip[i])
                $('<small class="ip">' + ip[i] + '</small>').appendTo(this.button)
            }
        }

    }

    var devices = []
 
    function getDevice(info) {
        for (var d of devices)
            if (d.info.host.toLowerCase() == info.host.toLowerCase()) return d;
        return null
    }


    var socket = io.connect(location.protocol + '//' + document.domain + ':' + location.port);

    /*
      SOCKETIO
    */

    socket.on('connect', function() {
        $('#devices').html('')
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

        for (var d of devices) {
            if (d.name == me) d.button.addClass('active')
            else d.button.removeClass('active')
        } 
    });

    socket.on('device-update', (state) => {
        state = JSON.parse(state)
        var dev = getDevice(state)

        if (!dev) {
            dev = new Device(state)
            devices.push(dev)

            devices.sort((a, b) => { return a.name.localeCompare(b.name) })
            $('#devices').html('')
            for (var d of devices) d.button.appendTo('#devices')

            if (showNotInteresting && !dev.interesting) dev.button.show()
        }

        dev.addIP(state.ip)

        for (var s in state.services)
            dev.addService(state.services[s])
                
    })

    socket.on('status', function(msg) {
        console.log('status:', msg)
    });


    $('#allBtn').on('click', () => {
        if (showNotInteresting) {
            $('#allBtn').removeClass('active')
            showNotInteresting = false
            $('#devices').find('.not-interesting').hide()
        } else {
            $('#allBtn').addClass('active')
            showNotInteresting = true
            $('#devices').find('.not-interesting').show()
        }
    })

});
