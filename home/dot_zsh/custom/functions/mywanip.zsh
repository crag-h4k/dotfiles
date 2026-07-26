#!/usr/bin/env zsh
# Network banner helpers: LAN interface detection, the physical link's public
# WAN IP, and - when a VPN is up - the VPN's public IP.
#
# Env:
#   MYWANIP_TTL  WAN cache lifetime in seconds (default: 300 = 5 min)
#
# Public commands: myip (LAN, in myip.zsh), mywanip (true WAN), myvpnip (VPN
# WAN), netbanner (the composed login line).
#
# Caveat: on a FULL-tunnel VPN (all routes via the tunnel) the kernel may route
# even interface-bound traffic through the VPN, so `mywanip` can mirror the VPN
# IP. On a split tunnel (the common corporate-VPN case) the physical link
# keeps an internet route and mywanip returns the true home/office public IP.

# Primary LAN interface: wired preferred, then wireless. Empty if none up.
function _net_lan_iface() {
    case "$OSTYPE" in
        darwin*)
            local port dev wired wifi line
            while IFS= read -r line; do
                case "$line" in
                    "Hardware Port: "*) port="${line#Hardware Port: }" ;;
                    "Device: "*)
                        dev="${line#Device: }"
                        [[ -n "$dev" ]] || continue
                        ipconfig getifaddr "$dev" >/dev/null 2>&1 || continue
                        case "$port" in
                            (*Ethernet*|*LAN*|*Thunderbolt*Bridge*) [[ -n "$wired" ]] || wired="$dev" ;;
                            (*Wi-Fi*|*AirPort*) [[ -n "$wifi" ]] || wifi="$dev" ;;
                        esac
                        ;;
                esac
            done < <(networksetup -listallhardwareports 2>/dev/null)
            print -r -- "${wired:-$wifi}"
            ;;
        linux*)
            local i wired wifi
            for i in $(ip -4 -o addr show up scope global 2>/dev/null | awk '{print $2}'); do
                case "$i" in
                    (lo|docker*|veth*|virbr*|br-*|tun*|tap*|gpd*|utun*|wg*|ppp*) continue ;;
                    (en*|eth*) [[ -n "$wired" ]] || wired="$i" ;;
                    (wl*) [[ -n "$wifi" ]] || wifi="$i" ;;
                esac
            done
            print -r -- "${wired:-$wifi}"
            ;;
    esac
}

# IPv4 of a given interface.
function _net_iface_ip4() {
    local iface="$1"
    [[ -n "$iface" ]] || return 1
    case "$OSTYPE" in
        darwin*) ipconfig getifaddr "$iface" 2>/dev/null ;;
        linux*)  ip -4 -o addr show "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1 ;;
    esac
}

# Interface carrying the default route (the VPN tunnel when one is up).
function _net_default_iface() {
    case "$OSTYPE" in
        darwin*) route -n get default 2>/dev/null | awk '/interface:/{print $2}' ;;
        linux*)  ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' ;;
    esac
}

# VPN interface name if the default route runs over a tunnel, else empty.
function _net_vpn_iface() {
    case "$(_net_default_iface)" in
        (utun*|ppp*|ipsec*|gpd*|tun*|tap*|wg*) print -r -- "$(_net_default_iface)" ;;
        (*) return 1 ;;
    esac
}

# Fetch public IPv4. $1 = optional source IP to bind (--interface accepts an IP
# without needing root, unlike binding a device name). Echoes IP, or fails.
function _net_public_ip() {
    local bind="$1" url ip
    local args=(-s -4 --max-time 2)
    [[ -n "$bind" ]] && args+=(--interface "$bind")
    for url in https://icanhazip.com https://checkip.amazonaws.com https://ifconfig.co; do
        ip=$(curl "${args[@]}" "$url" 2>/dev/null | tr -d '[:space:]')
        [[ "$ip" == <->.<->.<->.<-> ]] && { print -r -- "$ip"; return 0; }
    done
    return 1
}

# Cached public-IP lookup. $1 = cache key, $2 = optional bind source IP.
# On lookup failure falls back to the last cached value (even if stale) before
# giving up, so a flaky VPN does not flap the banner to <offline>.
function _net_cached_ip() {
    local key="$1" bind="$2"
    local tag="${bind//[^0-9A-Za-z]/_}"
    local cache="${TMPDIR:-/tmp}/.wanip-${key}-${tag}-$UID"
    local ttl=${MYWANIP_TTL:-300}
    if [[ -f "$cache" ]]; then
        local now mtime
        now=$(date +%s)
        # GNU stat: -c %Y. BSD stat: -f %m. Try GNU first.
        mtime=$(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null)
        if [[ -n "$mtime" ]] && (( now - mtime < ttl )); then
            cat "$cache"; return 0
        fi
    fi
    local ip
    if ip=$(_net_public_ip "$bind"); then
        print -r -- "$ip" | tee "$cache"
        return 0
    fi
    [[ -s "$cache" ]] && { cat "$cache"; return 0; }
    echo "<offline>"
}

# Public IP of the true LAN interface (bound to its source IP to bypass a
# split-tunnel VPN where possible; see the full-tunnel caveat above).
function mywanip() {
    _net_cached_ip "lan" "$(_net_iface_ip4 "$(_net_lan_iface)")"
}

# Public IP as seen through the VPN (default route). Fails if no VPN is up.
function myvpnip() {
    _net_vpn_iface >/dev/null || return 1
    _net_cached_ip "vpn" ""
}

# Compose the login banner: LAN, WAN, and (only when a VPN is up) VPN WAN.
function netbanner() {
    local out vpn
    out="%F{cyan}LAN:%f $(myip)   %F{cyan}WAN:%f $(mywanip)"
    if vpn=$(myvpnip); then
        out+="   %F{magenta}VPN WAN:%f ${vpn}"
    fi
    print -P "$out"
}
