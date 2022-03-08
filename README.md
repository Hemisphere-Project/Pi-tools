# Pi-tools
Tools for embedded

## Bootstrap
Bootstrap a fresh image for RaspberryPi with tools

### Create Arch image
- Create image using instructions here: https://archlinuxarm.org/platforms/armv8/broadcom/raspberry-pi-4
- IMPORTANT: add a 3rd partition (ext4) using fdisk or gparted

### Create Raspbian image
- download official RaspiOS minimal (no desktop) and burn it using etcher
- IMPORTANT: add a 3rd partition (ext4) using fdisk or gparted

### Bootsrap the image
- Plug ethernet cable
- Boot the Pi with the fresh image
- ssh into it, or use keyboard and screen (ARCH: alarm / alarm // RASPBIAN: pi / raspberry)
```
bash <(curl -s https://raw.githubusercontent.com/Hemisphere-Project/Pi-tools/main/bootstrap/bootstrap-arch-rpi.sh)
```

