"use strict";

const util      = require('util');
const spawn     = require('child_process').spawn;
const merge     = require('mout/object/merge');

const Server    = require('./_server');


class RpiServer extends Server {

  constructor(server, opts) {
    super(server, merge({
      fps : 12,
    }, opts));
  }

  get_feed() {
    var that = this
    var args = ['-t', '0', '-o', '-', '-w', this.options.width, '-h', this.options.height, '-fps', this.options.fps, '-pf', 'baseline', '-rot', '180', '-n']    
    console.log('raspivid', args);
    var streamer = spawn('raspivid', args);
    streamer.on("exit", function(code){
      console.log("Failure", code);
      that.running = false
    });

    return streamer.stdout;
  }

};



module.exports = RpiServer;
