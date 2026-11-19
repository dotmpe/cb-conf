us_sync_srv() {
    local conf="/etc/userconf/storage.conf"
    [ -r "$conf" ] && source "$conf"

    local id export_name vol_link vkind sub_target sub_link
    for id in "${!SRV_VOLUMES[@]}"; do
        export_name="${SRV_VOLUMES[$id]}"
        vol_link="${SRV_ROOT}/volume-${id}"

        # 1. Link /srv/volume-<id> -> /mnt/nfs/<export_name>
        sudo ln -sfn "${AUTOFS_BASE}/${export_name}" "$vol_link"

        # 2. Link /srv/<vkind>-<id> -> /srv/volume-<id>/<vkind>
        for vkind in "${SRV_VKINDS[@]}"; do
            sub_target="${vol_link}/${vkind}"
            sub_link="${SRV_ROOT}/${vkind}-${id}"
            
            # Ensure target directory exists on the backing volume before linking
            if [ -d "$vol_link" ]; then
                mkdir -p "$sub_target" 2>/dev/null
                sudo ln -sfn "$sub_target" "$sub_link"
            fi
        done
    done
    echo "Synced ${#SRV_VOLUMES[@]} volumes across ${#SRV_VKINDS[@]} vkinds in ${SRV_ROOT}."
}
