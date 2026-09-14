#!/usr/bin/env zsh
# ~/.zsh/custom/functions/vmssh.zsh
# vmssh - ssh into a VMware Fusion guest by VM name. Use it like ssh: pass any
# ssh options, flags, and remote command. The one argument that names a Fusion
# VM is swapped for the IP vmrun reports; everything else is handed to ssh
# untouched. Defaults to your login user; prefix user@<vm-name> to override.
#   vmssh worker
#   vmssh -v dane@worker -L 8080:localhost:80
#   vmssh worker uname -a
# macOS + Fusion only.

[[ "$OSTYPE" == darwin* ]] || return 0

function vmssh() {
    emulate -L zsh
    local vmroot="$HOME/Virtual Machines.localized"
    local -a a=("$@")
    local -a known=( "$vmroot"/*.vmwarevm(N:t:r) )
    local i idx=0 user="" name=""
    for (( i = 1; i <= ${#a}; i++ )); do
        local tok="${a[i]}" cand="${a[i]}"
        [[ "$cand" == *@* ]] && cand="${cand##*@}"
        if (( ${known[(Ie)$cand]} )); then
            idx=$i; name="$cand"
            [[ "$tok" == *@* ]] && user="${tok%@*}"
            break
        fi
    done
    if (( idx == 0 )); then
        print -u2 "vmssh: no known VM name in args (have: ${known[*]:-none})"
        return 2
    fi
    local vmx=( "$vmroot/${name}.vmwarevm/"*.vmx(N) )
    local ip
    ip=$(vmrun -T fusion getGuestIPAddress "${vmx[1]}") || return 1
    a[idx]="${user:-$USER}@${ip}"
    ssh "${a[@]}"
}

function _vmssh() {
    emulate -L zsh
    compadd -- "$HOME/Virtual Machines.localized/"*.vmwarevm(N:t:r)
}
compdef _vmssh vmssh 2>/dev/null
