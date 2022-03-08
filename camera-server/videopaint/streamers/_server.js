"use strict";


const WebSocketServer = require('ws').Server;
const Splitter        = require('stream-split');
const merge           = require('mout/object/merge');

const NALseparator    = new Buffer([0,0,0,1]);//NAL break


class _Server {

  constructor(server, options) {

    this.running = false

    this.options = merge({
        width : 960,
        height: 540,
        autoplay: false
    }, options);

    this.wss = new WebSocketServer({ server });

    this.new_client = this.new_client.bind(this);
    this.start_feed = this.start_feed.bind(this);
    this.broadcast  = this.broadcast.bind(this);

    this.wss.on('connection', this.new_client);
  }
  

  start_feed() {
    var that = this

    if (this.running) {
      console.log('Stream already started')
      this.readStream.destroy()
      setTimeout(()=>{
        that.running = false
        that.start_feed()
      }, 100)
      return 
    }

    var readStream = this.get_feed();
    this.readStream = readStream;
    this.running = true

    readStream = readStream.pipe(new Splitter(NALseparator));
    readStream.on("data", this.broadcast);
    readStream.on("end", (code) => {
      console.log("streamer eneded..")
      setTimeout(()=>{
        that.running = false
      }, 100)
    });
  }

  get_feed() {
    throw new Error("to be implemented");
  }

  broadcast(data) {
    var count = 0;
    this.wss.clients.forEach(function(socket) {
      if(socket.buzy)
        return;

      socket.buzy = true;
      socket.buzy = false;

      socket.send(Buffer.concat([NALseparator, data]), { binary: true}, function ack(error) {
        socket.buzy = false;
        // console.log('send data')
      });
    });
  }

  new_client(socket) {
  
    var self = this;
    console.log('New guy');

    socket.send(JSON.stringify({
      action : "init",
      width  : this.options.width,
      height : this.options.height,
      autoplay : this.options.autoplay
    }));

    if (this.options.autoplay) self.start_feed();

    socket.on("message", function(data){
      var cmd = "" + data, action = data.split(' ')[0];
      console.log("Incomming action '%s'", action);

      if(action == "REQUESTSTREAM")
        self.start_feed();
      if(action == "STOPSTREAM")
        self.readStream.pause();
    });

    socket.on('close', function() {
      self.readStream.end();
      console.log('stopping client interval');
    });
  }


};


module.exports = _Server;
