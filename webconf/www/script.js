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

            // title section
            let r = $('<div class="row section">').appendTo('#settings')
            $('<div class="col-3">').appendTo(r)
            $('<div class="col-6">').html('<div class="title">' + s[k]['title'] + '</div>').appendTo(r)

            // elements
            for (var j in s[k]['elements']) {
                var e = s[k]['elements'][j]

                let r = $('<div class="row">').appendTo('#settings').append('<div class="col-3">')
                $('<div class="col-2 text-right">').html(e['label']).appendTo(r)

                var i = null
                // text
                if (e['field'].startsWith('text')) {
                    i = $('<input type="text" size="' + e['field'].split('|')[1] + '" name="' + k+'.'+j + '" value="' + e['value'] + '">')
                }
                // select
                if (e['field'].startsWith('select')) {
                    i = $('<select name="' + k+'.'+j + '">')
                    $.each(e['field'].split('|')[1].split(','), function(k, v) {
                        // text[value]
                        let t = v.split('[')
                        let text = t[0]
                        let value = t[1].replace(']', '')
                        // console.log(value, text)
                        $('<option value="' + value + '">').html(text).appendTo(i)
                    })
                    i.val(e['value'])
                }

                $('<div class="col-2">').append(i).appendTo(r)
                $('<div class="col">').html(e['legend']).appendTo(r)
            }
        }
    })

    socket.on('status', function(msg) {
        console.log('status:', msg)
    });

    function send_update(values) {
        if (values === undefined) values = {}
        $.each($('#settings').serializeArray(), function(i, field) {
            console.log(field)
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

    // IFRAME STYLE
    if (window.location !== window.parent.location) {
        // $('.navbar').hide()
    }

});