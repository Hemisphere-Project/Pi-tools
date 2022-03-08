#!/usr/bin/env python3
import subprocess
import time

while True:
	flag = subprocess.check_output("ifconfig eth0 | grep flags |  cut -d'=' -f 2 | cut -d'<' -f 1", shell=True).strip()
	if int(flag) == 4163:
		try:
			net4 = subprocess.check_output("ifconfig eth0 | grep netmask", shell=True).strip()
			print ("ipv4 ok on eth0")
		except:
			print ("ipv4 missing.. restarting eth0")
			# subprocess.call("ifconfig eth0 down; sleep 3; ifconfig eth0 2.0.0.1 netmask 255.255.0.0 up;", shell=True)
			subprocess.call("ifconfig eth0 down; sleep 1; systemctl restart NetworkManager; sleep 3; ifconfig eth0 up;", shell=True)
	time.sleep(5)
