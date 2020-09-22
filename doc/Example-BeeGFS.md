# Example: BeeGFS Server Setup 

This guide shows how to setup a highly available BeeGFS file system on a pair of servers, based on `nvkeep` and `NVMesh` protected volumes.

## Prerequisites

For the sake of brevity, this guide makes the following assumptions:

- A pair of servers named `server01` and `server02`  to act as active/active BeeGFS servers.
  - NVMesh client preinstalled and the following NVMesh volumes created:
    - `bmgmtd-server01` - BeeGFS management service volume, primarily served by `server01`
    - `bmeta-server01` - BeeGFS metadata service volume, primarily served by `server01`
    - `bmeta-server02` - BeeGFS metadata service volume, primarily served by `server02`
    - `bstorage-server01` - BeeGFS storage service volume, primarily served by `server01`
    - `bstorage-server02` - BeeGFS storage service volume, primarily served by `server02` 
  - `keepalived`, `nvkeep` and `BeeGFS` packages are installed on both servers.
    - BeeGFS packages: `beegfs-mgmtd` `beegfs-meta` `beegfs-storage` `libbeegfs-ib`
  - Management network to use for keepalived heartbeats is configured on `eth0` on both servers with IP address `10.0.0.1` (server01) and `10.0.0.2` (server02).
  - Both servers have `ib0` as a high speed network interface to use for BeeGFS traffic, based on floating IP addresses `192.168.0.1` (server01) `192.168.0.2` (server02), which will be assigned by `nkveep`
- A client named `client01` to act as BeeGFS client and with access to the BeeGFS services over the high speed network (`192.168.0.100`).
  - BeeGFS packages to be installed: `beegfs-client` `beegfs-helperd` `beegfs-utils`

## Preparing the BeeGFS Services

### Prepare server01

On `server01`, prepare the BeeGFS services mountpoints.

```bash
hostnames=("server01" "server02")

for volumename in b{mgmtd,meta,storage}-${hostnames[0]} b{meta,storage}-${hostnames[1]}; do
   # Attach all the nvmesh volumes for both BeeGFS servers
   nvmesh_attach_volumes -a EXCLUSIVE_READ_WRITE $volumename
   # Create and mount the xfs file systems on top of each nvmesh volume
   mkdir -p /beegfs_export/$volumename
   mkfs.xfs /dev/nvmesh/$volumename
   mount /dev/nvmesh/$volumename /beegfs_export/$volumename
done
```

Now let's initialize the BeeGFS target directories and config files for [multi-mode](https://doc.beegfs.io/latest/advanced_topics/multimode.html) on `server01`.

```bash
hostnames=("server01" "server02")
floating_ip_server01="192.168.0.1"

# Create the multi-mode config dirs and files for BeeGFS meta and storage
mkdir /etc/beegfs/${hostnames[0]}.d /etc/beegfs/${hostnames[1]}.d
cp /etc/beegfs/beegfs-{mgmtd,meta,storage}.conf /etc/beegfs/${hostnames[0]}.d
cp /etc/beegfs/beegfs-{meta,storage}.conf /etc/beegfs/${hostnames[1]}.d

# Initialize the management service target dir
/opt/beegfs/sbin/beegfs-setup-mgmtd -p /beegfs_export/bmgmtd-${hostnames[0]} -c /etc/beegfs/${hostnames[0]}.d/beegfs-mgmtd.conf

# Loop: Init BeeGFS target dirs and config files for meta and storage
for hostname in ${hostnames[@]}; do

   # Call beegfs-setup tools for meta and storage
   # (Optional: Add "-s ${hostname//[a-z]}" below for numeric IDs based on hostname)
   /opt/beegfs/sbin/beegfs-setup-meta -p /beegfs_export/bmeta-${hostname} -S bmeta-${hostname} -m ${floating_ip_server01} -c /etc/beegfs/${hostname}.d/beegfs-meta.conf
   /opt/beegfs/sbin/beegfs-setup-storage -p /beegfs_export/bstorage-${hostname} -S bstorage-${hostname} -m ${floating_ip_server01} -c /etc/beegfs/${hostname}.d/beegfs-storage.conf

   # Set unique log files to avoid conflicts when all services run on same host
   sed -i "s@^\(logStdFile.*\)=.*@\1= /var/log/beegfs-meta-${hostname}.log@" /etc/beegfs/${hostname}.d/beegfs-meta.conf
   sed -i "s@^\(logStdFile.*\)=.*@\1= /var/log/beegfs-storage-${hostname}.log@" /etc/beegfs/${hostname}.d/beegfs-storage.conf

done

# Set unique ports for server02 to avoid conflicts when all services run on same host
sed -i "s@^\(connMetaPort.*\)=.*@\1= 8105@" /etc/beegfs/${hostnames[1]}.d/beegfs-meta.conf
sed -i "s@^\(connStoragePort.*\)=.*@\1= 8103@" /etc/beegfs/${hostnames[1]}.d/beegfs-storage.conf

# (Optional: Configure BeeGFS connNetFilerFile for mgmtd/meta/storage/client for the
# floating IP subnet, in this example "192.168.0.0/24", in case there are other
# IP subnets that should not be used by BeeGFS.)
```

### Prepare server02

On `server02`, we need to prepare everything for it to be able to take ownership of all the BeeGFS services.

```bash
hostnames=("server01" "server02")

# Create the directories for the BeeGFS target mountpoints
for volumename in b{mgmtd,meta,storage}-${hostnames[0]} b{meta,storage}-${hostnames[1]}; do
   mkdir -p /beegfs_export/$volumename
done

# Copy the prepared config files from server01
scp -r ${hostnames[0]}:/etc/beegfs/*.d /etc/beegfs/
```

## Configure Nvkeep 

On `server01` (which will become `HOST_A` of our HOST_A / HOST_B high availability pair) prepare the nvkeep_service.conf from the empty template file:

```bash
cp /etc/nvkeep/nvkeep_service.conf.TEMPLATE /etc/nvkeep/nvkeep_service.conf
```

Now edit the `/etc/nvkeep/nvkeep_service.conf` file using your favorite text editor and fill in the info that we defined in the previous sections. (The nvkeep_service.conf will be sourced by a bash script, thus uses bash syntax.)

Note that the assignment of services to HOST_A / HOST_B below defines on which host the services will run preferably while both hosts are up.

```bash
# The hostnames of our HA server pair
HOSTNAME_HOST_A="server01"
HOSTNAME_HOST_B="server02"
# The management network interface to be used for keepalived heartbeats
STATIC_INTERFACE_HOST_A="eth0"
STATIC_INTERFACE_HOST_B="eth0"
# The static IP address of each host for heartbeats on the management network
STATIC_IPADDR_HOST_A="10.0.0.1"
STATIC_IPADDR_HOST_B="10.0.0.2"
# The high speed network interface for BeeGFS, used for the floating IP address
FLOATING_INTERFACES_HOST_A=("ib0")
FLOATING_INTERFACES_HOST_B=("ib0")
# The floating IP addresses that will be moved between hosts in case of host failure
FLOATING_IPADDRS_HOST_A=("192.168.0.1/24")
FLOATING_IPADDRS_HOST_B=("192.168.0.2/24")
# The NVMesh volumes that will be moved between hosts in case of host failure
NVMESHVOLS_HOST_A=( {mgmtd,meta,storage}-${HOSTNAME_HOST_A} )
NVMESHVOLS_HOST_B=( {meta,storage}-${HOSTNAME_HOST_B} )
# The mountpoints that will be moved between hosts in case of host failure
MOUNTPOINTS_HOST_A=("/beegfs_export/bmgmtd-server01" "/beegfs_export/bmeta-server01" "/beegfs_export/bstorage-server01")
MOUNTPOINTS_HOST_B=("/beegfs_export/bmeta-server02" "/beegfs_export/bstorage-server02")
# The name of the systemd services to move between hosts in case of host failure
SERVICES_HOST_A=(beegfs-{mgmtd,meta,storage}@${HOSTNAME_HOST_A} )
SERVICES_HOST_B=(beegfs-{meta,storage}@${HOSTNAME_HOST_B} )
```

### Configure nvkeep fstab

nvkeep uses a separate fstab for its mountpoints, which has the same syntax as the normal `/etc/fstab`. Start by copying the fstab from the empty template file on `server01`:

```bash
cp /etc/nvkeep/fstab.TEMPLATE /etc/nvkeep/fstab
```

Now fill in the mountpoint info for our nvkeep-protected NFS service by editing `/etc/nvkeep/fstab` using your favorite text editor:

```
/dev/nvmesh/bmgmtd-server01    /beegfs_export/bmgmtd-server01    xfs  defaults  0 0
/dev/nvmesh/bmeta-server01     /beegfs_export/bmeta-server01     xfs  defaults  0 0
/dev/nvmesh/bmeta-server02     /beegfs_export/bmeta-server02     xfs  defaults  0 0
/dev/nvmesh/bstorage-server01  /beegfs_export/bstorage-server01  xfs  defaults  0 0
/dev/nvmesh/bstorage-server02  /beegfs_export/bstorage-server02  xfs  defaults  0 0
```

(Optional: Apply tunings instead of "defaults" mount arguments in fstab.)

## Apply nvkeep config

Running the `nvkeep_appy_config` tool on `server01` (`HOST_A`) will create the `/etc/keepalived.conf` file on both servers and copy the `nvkeep_service.conf` and nvkeep `fstab` to `server02` (`HOST_B`) via `ssh`/`scp`:

``` bash
nvkeep_apply_config
```

## Starting the nvkeep-protected BeeGFS Services

When you run the keepalived service now on `server01`, it will become the master for the configured services and bring up all configured resources:

```
server01: systemctl restart keepalived
```

You can now confirm that everything is up and running as intended by using the `nvkeep_check_status` tool on `server01`. (It might take a few seconds until everything is up.)

```bash
server01: nvkeep_check_status

[OK] VOLUME: bmgmtd-server01, ...
[OK] MOUNTPOINT: /beegfs_export/bmgmtd-server01, ...
[OK] FLOATING IP: ib0 192.168.0.1/24, ...
[OK] SERVICE: beegfs-mgmtd@server01, ...
```

If something is not ok, you can find keepalived log messages in syslog (`/var/log/messages`), the events delivered by keepalived to nvkeep in `/var/log/nvkeep/event_handler.log` and the corresponding actions based on received events in `/var/log/nvkeep/actions.log`.

When everyting looks good, proceed by running keepalived on `server02`, which will migrate server02's preferred services and can again be verified via `nvkeep_check_status` on `server02` after a few seconds:

```bash
server02: systemctl restart keepalived
```

## Mounting the BeeGFS client

The server side is up and running, so now it's time to connect our BeeGFS client. Run the following commands on `client01` to mount the BeeGFS using the floating IP address of `server01`:

```bash
/opt/beegfs/sbin/beegfs-setup-client -m 192.168.0.1
# (Optional: Depending on whether you installed OFED RDMA drivers, you might need to set
# the driver path in /etc/beegfs/beegfs-client-autobuild.conf)
# (Optional: Set /etc/beegfs/connNetFilterFile in beegfs-client.conf to the floating IP
# subnet.)
systemctl start beegfs-helperd
systemctl start beegfs-client
```

Now your BeeGFS client is ready for use. The `beegfs-net` command can confirm that the client is able to connect to the servers.

## Simulating Server Failure

The easiest way to test what happens in case of server failure is to shutdown the resources on `server01` and stop keepalived:

```bash
server01: nvkeep_clean_shutdown
```

The `nvkeep_check_status` command on `server02` will show you that the failover happens within a couple of seconds. It takes a bit longer for the BeeGFS client to retry the connection and resume its normal operation.

```bash
server02: nvkeep_check_status

Checking peer host services on localhost...

[OK] VOLUME: bmgmtd-server01, ...
[OK] MOUNTPOINT: /beegfs_export/bmgmt-server01, ...
[OK] FLOATING IP: ib0 192.168.0.1/24, ...
[OK] SERVICE: beegfs-mgmtd@server01, ...
```

After verifying that the failover worked as expected, bring back everything to normal on `server01` by simply restarting its keepalived service:

```bash
server01: systemctl restart keepalived
```

## Additional Notes: Keepalived Autostart or not

Make sure to check the additional notes section about `keepalived` autostart on system boot in the [readme](../README.md).
