#!/usr/bin/bash
#
# upgrade-ufds.sh:
#   - NOTE: If this is the UFDS master, then, in general, all slaves should
#     disable ufds-replicator until they themselves have been upgraded.
#     Typically this should only be required for UFDS postgres schema
#     migrations.
#   - TODO: can we put portal in RO mode?
#   - moray backup of ufds buckets
#   - provision ufds1 zone and wait until in DNS (presuming curr UFDS is 'ufds0')
#   - stop ufds0 zone
#   - run `backfill` in moray zone (the backfill script is to fill in values
#     for newly added indexes in the UFDS bucket in moray)
#   - upgrade ufds0 and wait until in DNS
#   - stop ufds1 (we don't need it anymore, delete it eventually)
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit
set -o pipefail

TOP=$(cd $(dirname $0)/; pwd)
source $TOP/libupgrade.sh


#---- mainline

# -- Check usage and skip out if no upgrade necessary.

if [[ $# -ne 1 ]]; then
    fatal "Usage: upgrade-ufds.sh upgrade-images"
fi
[[ ! -f "$1" ]] && fatal "'$1' does not exist"
source $1

if [[ -z ${UFDS_IMAGE} ]]; then
    fatal "\$UFDS_IMAGE not defined"
fi
[[ $(sysinfo | json "Boot Parameters.headnode") == "true" ]] \
    || fatal "not running on the headnode"

SDC_APP=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
[[ -n "$SDC_APP" ]] || fatal "could not determine 'sdc' SAPI app"
UFDS_SVC=$(sdc-sapi /services?name=ufds\&application_uuid=$SDC_APP | json -H 0.uuid)
[[ -n "$UFDS_SVC" ]] || fatal "could not determine sdc 'ufds' SAPI service"
UFDS_DOMAIN=$(bash /lib/sdc/config.sh -json | json ufds_domain)
[[ -n "$UFDS_DOMAIN" ]] || fatal "no 'ufds_domain' in sdc config"

# Get the old zone. Assert we have exactly one on the HN.
UFDS_ADMIN_UUID=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
CUR_UUID=$(vmadm lookup -1 state=running owner_uuid=$UFDS_ADMIN_UUID alias=~ufds)
[[ -n "${CUR_UUID}" ]] \
    || fatal "there is not exactly one running ufdsN zone";
CUR_ALIAS=$(vmadm get $CUR_UUID | json alias)
CUR_IMAGE=$(vmadm get $CUR_UUID | json image_uuid)

# Don't bother if already on this image.
if [[ $CUR_IMAGE == $UFDS_IMAGE ]]; then
    echo "$0: already using image $CUR_IMAGE for zone $CUR_UUID ($CUR_ALIAS)"
    exit 0
fi


# -- Assert (until CAPI-364 fixed) that 'manatee_admin_ips' in the 'sdc'
#    application is the current manatee primary IP
manatee_primary_ip=$(sdc-login manatee 'source .bashrc; manatee-stat' </dev/null | json sdc.primary.ip)
manatee_admin_ips=$(sdc-sapi /applications?name=sdc | json -H 0.metadata.manatee_admin_ips)
if [[ "$manatee_primary_ip" != "$manatee_admin_ips" ]]; then
    fatal "SDC app 'manatee_admin_ips' ($manatee_admin_ips) != Manatee " \
        "primary ip ($manatee_primary_ip). This will break on CAPI-364."
fi


# -- Get the new image.
./download-image.sh $UFDS_IMAGE || fatal "failed to download image $UFDS_IMAGE"


# -- Do the UFDS upgrade.

# Backup data.
sdc-login manatee "pg_dump -U moray -t 'ufds*' moray" >./moray_ufds_backup.sql


# Update UFDS service in SAPI.
# WARNING: hardcoded values here, should really derive from canonical ufds
# service JSON somewhere.
sapiadm update $UFDS_SVC params.max_physical_memory=8192
sapiadm update $UFDS_SVC params.max_locked_memory=8192
sapiadm update $UFDS_SVC params.max_swap=8448
sapiadm update $UFDS_SVC params.image_uuid=$UFDS_IMAGE
update_svc_user_script $CUR_UUID $UFDS_IMAGE

# Provision a new ufds instance.
CUR_N=$(echo $CUR_ALIAS | sed -E 's/ufds([0-9]+)/\1/')
NEW_N=$(( $CUR_N + 1 ))
NEW_ALIAS=ufds$NEW_N
cat <<EOM | sapiadm provision
{
    "service_uuid": "$UFDS_SVC",
    "params": {
        "owner_uuid": "$UFDS_ADMIN_UUID",
        "alias": "$NEW_ALIAS"
    }
}
EOM
NEW_UUID=$(vmadm lookup -1 alias=$NEW_ALIAS)
[[ -n "$NEW_UUID" ]] || fatal "could not find new $NEW_ALIAS zone"

# Wait for new IP to enter DNS.
wait_until_zone_in_dns $NEW_UUID $NEW_ALIAS $UFDS_DOMAIN

# Stop old ufds.
vmadm stop $CUR_UUID


# Backfill.
# Work around EPIPE in 'vmadm lookup' (OS-2604)
MORAY_UUIDS=$(vmadm lookup alias=~^moray owner_uuid=$UFDS_ADMIN_UUID state=running)
MORAY_UUID=$(echo "$MORAY_UUIDS" | head -1)
echo "Backfill (stage 1)"
zlogin $MORAY_UUID /opt/smartdc/moray/build/node/bin/node \
    /opt/smartdc/moray/node_modules/.bin/backfill \
    -i name -i version -i givenname -i expires_at -i company \
    -P objectclass=sdcimage \
    -P objectclass=sdcpackage \
    -P objectclass=amonprobe \
    -P objectclass=amonprobegroup \
    -P objectclass=datacenter \
    -P objectclass=authdev \
    -P objectclass=foreigndc \
    ufds_o_smartdc </dev/null

echo "Backfill (stage 2)"
zlogin $MORAY_UUID /opt/smartdc/moray/build/node/bin/node \
    /opt/smartdc/moray/node_modules/.bin/backfill \
    -i name -i version -i givenname -i expires_at -i company \
    -P objectclass=sdckey \
    ufds_o_smartdc </dev/null


# Upgrade "old" ufds zone.
# TODO: I *believe* we can have two UFDS' running during backfill.
echo '{}' | json -e "this.image_uuid = '${UFDS_IMAGE}'" |
    vmadm reprovision ${CUR_UUID}


echo "Backfill (stage 3)"
zlogin $MORAY_UUID /opt/smartdc/moray/build/node/bin/node \
    /opt/smartdc/moray/node_modules/.bin/backfill \
    -i name -i version -i givenname -i expires_at -i company \
    ufds_o_smartdc </dev/null


# -- Phase out the "NEW" ufds zone. Just want to keep the original "CUR" one.
wait_until_zone_in_dns $CUR_UUID $CUR_ALIAS $UFDS_DOMAIN
zlogin $NEW_UUID svcadm disable registrar
wait_until_zone_out_of_dns $NEW_UUID $NEW_ALIAS $UFDS_DOMAIN
vmadm stop $NEW_UUID

set +o xtrace
echo ''
echo '* * *'
echo "Run the following to destroy the $NEW_ALIAS instance used for upgrade."
echo 'This is not done automatically because paranoia. It has been stopped.'
echo "    sdc-sapi /instances/$NEW_UUID -X DELETE"
echo '* * *'
echo "Done."