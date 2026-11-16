#!/bin/sh

# The spruce login (password happygaming) for spruce's dropbear and Samba on a base whose own
# /etc/passwd lacks it. Bind-mounted copies, never written to the base's files; a reboot drops
# them. Shared by the BaseOS platforms (H700 Anbernic XX, GKD 350H Ultra on BasedOS).
add_spruce_system_user() {
    grep -q '^spruce:' /etc/passwd 2>/dev/null && return 0

    SP_HASH='$6$spruceos00$.nwqRlVkLe.wmkXcEHXcu127ZFxpFQ.8JDbdh4CRd.FbF5biVcIl9qeE9T6QNAbbJaFKp3MLUwlaPUN0alXcl.'
    cp /etc/passwd /tmp/spruce_passwd || return 0
    cp /etc/shadow /tmp/spruce_shadow || return 0
    echo 'spruce:x:0:0:spruce:/root:/bin/sh' >> /tmp/spruce_passwd
    echo "spruce:${SP_HASH}:19000:0:99999:7:::" >> /tmp/spruce_shadow
    chmod 644 /tmp/spruce_passwd
    chmod 600 /tmp/spruce_shadow
    mount -o bind /tmp/spruce_passwd /etc/passwd
    mount -o bind /tmp/spruce_shadow /etc/shadow
}
