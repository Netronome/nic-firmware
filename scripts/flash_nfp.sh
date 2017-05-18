#ToDo - Skip nfp-one command for Starfighter/Starshuttle 

/opt/netronome/bin/nfp-flash --i-accept-the-risk-of-overwriting-miniloader --preserve-media-overrides -w /opt/netronome/flash/flash-nic.bin
yes | /opt/netronome/bin/nfp-one
reboot
