# twr
twr is a portable, wifi connected, four node Kubernetes cluster. It also
includes a fifth server board which acts as a wifi router for the cluster and
provides an endpoint with loadbalancing and proxying requests to the Kubernetes
API.

## Hardware, OS overview
Stack of five Udoo x86 Adv boards with SSD storage attached and an 8 port switch
connecting them all together. Each server runs Ubuntu server 16.04, though the
topmost board runs the same version of Desktop to ease the connection to wifi.
The four server nodes have swap disabled to comply with Kubeadm requirements.

### Board layout
Physically from top to bottom, here are the hostnames of each board:
twr (router and reverse proxy)
node-1 (Kubernetes tainted master)
node-2 (Kubernetes worker)
node-3 (Kubernetes worker)
node-4 (Kubernetes worker)

## twr board
The twr board (topmost) uses iptables to NAT the cluster and give internet
access, while using Nginx to provide access to both the Kubernetes API and to
whatever web services run on the cluster.

### Security
The iptables rules in the configuration aren't designed to be particularly
secure. It may be easy to gain access to the cluster from wifi and should
therefore not be used in its current state outside of trusted networks.

## Kubernetes cluster
Installation of Kubernetes cluster is based on:
https://blog.alexellis.io/kubernetes-in-10-minutes/

## Installation
The `deploy-servers.sh` script has been created to do most of the heavy lifting.
It expects a particular readiness state, however, which is detailed below.

### Manual, pre script steps
- twr board has connection to internet, wired static IP of `192.168.199.1/24`
- each board has a `k8s` user account with a known password and sudo access
- each board has an SSH server running
- workstation has `twr` entry in its hostsfile

### Installation script
- run first from workstation with `router` option
- once complete, make sure all nodes are able to get IP addresses from `twr`
- log onto `twr` and run the script from there with the `install-cluster` option
