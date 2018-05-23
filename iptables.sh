#!/bin/bash -eu

ALL_INTERFACES="$(ip a show scope global | grep '^[0-9]:' | cut -d' ' -f2 | tr -d ':')"
INTERNAL_INTERFACES=""
EXTERNAL_INTERFACES=""
for interface in ${ALL_INTERFACES}; do
    if grep forever <(ip a show scope global dev ${interface}); then
        INTERNAL_INTERFACES="${INTERNAL_INTERFACES} ${interface}"
    else
        EXTERNAL_INTERFACES="${EXTERNAL_INTERFACES} ${interface}"
    fi
done

/sbin/iptables -F
/sbin/iptables -P INPUT DROP
/sbin/iptables -P OUTPUT ACCEPT
/sbin/iptables -P FORWARD ACCEPT

for interface in ${INTERNAL_INTERFACES}; do
    /sbin/iptables -A INPUT -i ${interface} -j ACCEPT
done
/sbin/iptables -A INPUT -i lo -j ACCEPT
for interface in ${EXTERNAL_INTERFACES}; do
    /sbin/iptables -t nat -A POSTROUTING -o ${interface} -j MASQUERADE
done
/sbin/iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
/sbin/iptables -A INPUT -p tcp -m tcp -m multiport --dports 22,80,6443 -j ACCEPT
