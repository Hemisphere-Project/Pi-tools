$(document).ready(function() {

    var me = ""

    var socket = io.connect(location.protocol + '//' + document.domain + ':' + location.port);
    var last_status;
    var last_status_str;

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

    socket.on('settings', (s) => {
        $('#settings').empty()

        for (var k in s) {
            let r = $('<div class="row">').appendTo('#settings')
            $('<div class="col-3 text-right">').html(s[k]['label']).appendTo(r)

            var i = null
            if (s[k]['field'].startsWith('text')) {
                i = $('<input type="text" size="' + s[k]['field'].split('|')[1] + '" name="' + k + '" value="' + s[k]['value'] + '">')

            }

            $('<div class="col-2">').append(i).appendTo(r)
            $('<div class="col">').html(s[k]['legend']).appendTo(r)
        }
    })

    socket.on('status', function(msg) {
        console.log('status:', msg)
    });

    function send_update(values) {
        if (values === undefined) values = {}
        $.each($('#settings').serializeArray(), function(i, field) {
            values[field.name] = field.value;
        });
        socket.emit('update', values);
    }


    // BUTTONS
    $('#save_btn').on('click', () => {
        send_update({ 'reboot': false })
    })

    $('#savereboot_btn').on('click', () => {
        send_update({ 'reboot': true })
    })

});