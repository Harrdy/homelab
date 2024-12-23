#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/check_wireguard_config.sh"

log_error() {
    echo -e "$(date): ${RED}[ERROR]${NC} $1" >&2
}

log_info() {
    echo -e "$(date): ${GREEN}[INFO]${NC} $1"
}

log_address() {
    echo -e "${CYAN}$1${NC}"
}

check_ping() {
    local target="$1"
    if [[ "$target" =~ ^\[.*\]$ ]]; then
        target=${target:1:-1}
    fi
    ping6 -c "$PING_COUNT" -W 5 "$target" > /dev/null 2>&1
}

check_tunnel() {
    local check_ip="$1"
    ping -c "$PING_COUNT" -W 5 "$check_ip" > /dev/null 2>&1
}

get_current_endpoint() {
    local wg_interface="$1"
    wg show "$wg_interface" endpoints 2>/dev/null | awk '{print $2}' | sed -E 's/\[?([0-9a-f:]+)\]?.*/\1/'
}

resolve_ipv6() {
    local target="$1"
    if [[ "$target" =~ ^\[?[0-9a-fA-F:]+\]?$ ]]; then
        echo "${target//[\[\]]/}"
        return
    fi

    local ipv6=$(getent ahosts "$target" | awk '/^[0-9a-f:]+/{print $1; exit}')
    if [[ -z "$ipv6" ]]; then
        log_error "IPv6-Adresse für $target konnte nicht aufgelöst werden."
    fi
    echo "$ipv6"
}

restart_wireguard() {
    local wg_interface="$1"
    log_error "Neustart von $wg_interface..."
    wg-quick down "$wg_interface" > /dev/null 2>&1
    sleep 2
    wg-quick up "$wg_interface" > /dev/null 2>&1
}

handle_tunnel_ip() {
    local wg_interface="$1"
    local tunnel_ip="$2"

    log_info "Prüfe, ob Tunnel-IP $(log_address "$tunnel_ip") erreichbar ist..."
    if check_tunnel "$tunnel_ip"; then
        log_info "Tunnel-IP $(log_address "$tunnel_ip") ist erreichbar."
    else
        log_error "Tunnel-IP $(log_address "$tunnel_ip") ist nicht erreichbar. Neustart von $wg_interface..."
        restart_wireguard "$wg_interface"
        sleep 5
        if check_tunnel "$tunnel_ip"; then
            log_info "Tunnel-IP $(log_address "$tunnel_ip") ist nach Neustart von $wg_interface wieder erreichbar."
        else
            log_error "Tunnel-IP $(log_address "$tunnel_ip") bleibt unerreichbar. $wg_interface wird gestoppt."
            wg-quick down "$wg_interface"
        fi
    fi
}

check_and_restart() {
    local target="$1"
    local wg_interface="$2"
    local tunnel_ip="$3"

    log_info "Teste Verbindung zu $(log_address "$target") über $wg_interface..."

    if check_ping "$target"; then
        local current_endpoint=$(get_current_endpoint "$wg_interface")
        local resolved_ipv6=$(resolve_ipv6 "$target")

        if [[ -z "$resolved_ipv6" ]]; then
            log_error "Auflösung von $(log_address "$target") fehlgeschlagen. Überspringe Überprüfung."
            return
        fi

        if [[ "$current_endpoint" == "$resolved_ipv6" ]]; then
            log_info "$(log_address "$target") ist erreichbar, und der Endpoint stimmt überein ($(log_address "$current_endpoint"))."
        else
            log_error "Endpoint stimmt nicht überein: aktuell $(log_address "$current_endpoint"), erwartet $(log_address "$resolved_ipv6")."
            restart_wireguard "$wg_interface"
        fi
    else
        log_error "$(log_address "$target") ist nicht erreichbar. Stoppe $wg_interface und warte 2 Minuten..."
        wg-quick down "$wg_interface"
        sleep 120

        if check_ping "$target"; then
            log_info "$(log_address "$target") ist nach 2 Minuten wieder erreichbar."
            wg-quick up "$wg_interface"
        else
            log_error "$(log_address "$target") ist weiterhin nicht erreichbar. Neustart von $wg_interface..."
            restart_wireguard "$wg_interface"

            if check_ping "$target"; then
                log_info "$(log_address "$target") ist nach dem Neustart von $wg_interface wieder erreichbar."
            else
                log_error "$(log_address "$target") bleibt auch nach Neustart von $wg_interface unerreichbar."
            fi
        fi
    fi

    handle_tunnel_ip "$wg_interface" "$tunnel_ip"
}

report_kuma() {
    local interface="$1"
    local url="$2"

    curl "$url" || echo "Fehler beim Aufruf der URL $url."
}

for i in "${!TARGETS[@]}"; do
    check_and_restart "${TARGETS[$i]}" "${WG_INTERFACES[$i]}" "${TUNNEL_CHECK_IPS[$i]}"

    if ! check_tunnel "${TUNNEL_CHECK_IPS[$i]}"; then
        report_kuma "${interfaces[${WG_INTERFACES[$i]}]}"
    fi

    if [ $i -lt $((${#TARGETS[@]} - 1)) ]; then
        echo
    fi
done
