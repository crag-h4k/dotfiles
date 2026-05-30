#!/usr/bin/env zsh
# Print the LAN IPv4 of the primary physical interface: wired preferred, then
# wireless. Excludes loopback, VPN tunnels, and virtual bridges. Fresh on every
# call (not cached), so it tracks network changes. Interface-detection helpers
# live in mywanip.zsh (all custom functions are sourced before first use).
function myip() {
    local iface ip
    iface=$(_net_lan_iface)
    [[ -n "$iface" ]] && ip=$(_net_iface_ip4 "$iface")
    echo "${ip:-<offline>}"
}
