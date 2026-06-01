#!/system/bin/sh
# Block outbound internet except private LAN ranges and local DNS.
# Requires root. Applied automatically on boot via install_persistent.ps1.

LOG=/data/local/frame-sync/firewall.log
LAN_DNS=192.168.1.1

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

if [ "$(id -u)" != "0" ]; then
    echo "root required"
    exit 1
fi

# Remove our old rules if re-applying
iptables -D fw_OUTPUT -j FRAME_WAN 2>/dev/null
iptables -F FRAME_WAN 2>/dev/null
iptables -X FRAME_WAN 2>/dev/null

iptables -N FRAME_WAN
iptables -A FRAME_WAN -o lo -j RETURN
iptables -A FRAME_WAN -m state --state ESTABLISHED,RELATED -j RETURN
iptables -A FRAME_WAN -d 127.0.0.0/8 -j RETURN
iptables -A FRAME_WAN -d 192.168.0.0/16 -j RETURN
iptables -A FRAME_WAN -d 10.0.0.0/8 -j RETURN
iptables -A FRAME_WAN -d 172.16.0.0/12 -j RETURN
iptables -A FRAME_WAN -d 169.254.0.0/16 -j RETURN
iptables -A FRAME_WAN -p udp -d "$LAN_DNS" --dport 53 -j RETURN
iptables -A FRAME_WAN -p tcp -d "$LAN_DNS" --dport 53 -j RETURN
iptables -A FRAME_WAN -j REJECT

iptables -I fw_OUTPUT 1 -j FRAME_WAN 2>/dev/null || iptables -I OUTPUT 1 -j FRAME_WAN

log "LAN-only firewall applied (DNS via $LAN_DNS)"
