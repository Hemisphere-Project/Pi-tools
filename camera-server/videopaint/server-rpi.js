"use strict";

/**
* Run this on a raspberry pi 
* then browse (using google chrome/firefox) to http://[pi ip]:8080/
*/


const http    = require('http');
const express = require('express');
const fs = require('fs');
const cors = require('cors');
const bodyParser = require('body-parser');
const WebStreamerServer = require('./streamers/raspivid');
const app  = express();

const osc = require('node-osc');


// HPlayer OSC pipe
const oscclient = new osc.Client('127.0.0.1', 4000);

//public website
app.use(express.static(__dirname + '/www'));


//add other middleware
app.use(cors());
app.use(bodyParser.json({limit: '16mb'}));                         
app.use(bodyParser.urlencoded({ extended: false, limit: '16mb' }));
app.use(bodyParser.raw({ inflate: true, limit: '16mb', type: 'application/octet-stream' }));

// receive image
app.post('/image', async (req, res) => {
    if (!req.body) {
        res.status(404).send({
            status: false,
            message: 'No imgData provided..'
        });
    } else {
        let imgData = req.body
        fs.writeFile('/tmp/videopaint.jpg', imgData, (err)=>{
            if (err) return console.log(err);
            
            //relay to HPlayer using OSC
            oscclient.send('/play', '/tmp/videopaint.jpg', () => {
                // oscclient.close();
            });

            //send response
            res.send({ status: true });
        });
        
        
    }
});


const server  = http.createServer(app);
const silence = new WebStreamerServer(server, {fps: 10, width: 640, height:480, autoplay: true});

server.listen(8080);
