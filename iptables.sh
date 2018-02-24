#/bin/bash

iptables -A FORWARD -i enp2s0 -j ACCEPT
iptables -t nat -A POSTROUTING -o wlp3s0 -j MASQUERADE
