import sys, os
from flaskserver import FlaskServer

config = { "port": 4038 }

# RUN flag
import signal, sys, threading
run = threading.Lock()
run.acquire()

# CTRL-C handler
def ctrlC(signal, frame):
    run.release()
signal.signal(signal.SIGINT, ctrlC)

# START SERVER
flask = FlaskServer(config['port'])
flask.start()



# WAIT for CTRL-C
run.acquire()

flask.stop()

print("Goodbye !")
os.system("fuser -k "+str(config['port'])+"/tcp")
