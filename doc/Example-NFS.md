# Example: NFS Server Setup 

This guide shows how to setup a highly available NFS service on a pair of servers, based on `nvkeep` and `NVMesh` protected volumes.

## Prerequisites

For the sake of brevity, this guide makes the following assumptions:

- A pair of servers named `server01` and `server02`  to act as master and backup host for the NFS service.
  - NVMesh client preinstalled and a volume named `nfsvolume` has been created, on top of which an xfs file system will be exported through NFS.
  - `Keepalived` and `nvkeep` are installed on both servers.
  - Management network to use for keepalived heartbeats is configured on `eth0` on both servers with IP address `10.0.0.1` (server01) and `10.0.0.2` (server02).
  - Both servers have `ib0` as a high speed network interface to use for NFS traffic, based on a floating IP address (`192.168.0.1`), which will be assigned by `nkveep`
- A client named `client01` to act as NFS client and with access to the NFS service over the high speed network (`192.168.0.100`).

## Preparing the NFS Service

### Prepare server01

On `server01`, prepare the NFS service and exports file.

(Note: This example is for RHEL/CentOS. On Ubuntu, the NFS service is called `nfs-kernel-server`.)

```bash
# Attach the nvmesh volume for our NFS server
nvmesh_attach_volumes -a EXCLUSIVE_READ_WRITE nfsvolume
# Create an xfs file system on the nvmesh volume
mkfs.xfs /dev/nvmesh/nfsvolume
# Create the directory for the export mountpoint
mkdir /mnt/nfsexport
# If you haven't done it yet, install the nfs-utils which includes the nfs-server
yum install nfs-utils
# Disable automatic start of the nfs-server, because nvkeep will take care of that
systemctl disable nfs-server
```

Now let's edit the `/etc/exports` file for the NFS service on `server01` using your favorite text editor and add the following line:

```bash
/mnt/nfsexport *(rw,sync,sec=sys,no_root_squash)
```

### Prepare server02

On `server02`, we need to prepare everything for it to be able to run the NFS service in case its peer fails.

```bash
# Create the directory for the export mountpoint
mkdir /mnt/nfsexport
# Install the nfs-utils package containing the nfs-server
yum install nfs-utils
# Disable automatic start of the nfs-server, because nvkeep will take care of that
systemctl disable nfs-server
# Copy the prepared /etc/exports file from server01
scp server01:/etc/exports /etc/exports
```

## Configure nvkeep 

On `server01` (which will become `HOST_A` of our HOST_A / HOST_B high availability pair) prepare the nvkeep_service.conf from the empty template file:

```bash
cp /etc/nvkeep/nvkeep_service.conf.TEMPLATE /etc/nvkeep/nvkeep_service.conf
```

Now edit the `/etc/nvkeep/nvkeep_service.conf` file using your favorite text editor and fill in the info that we defined in the previous sections. (The nvkeep_service.conf will be sourced by a bash script, thus uses bash syntax.)

Note: In this example, only `server01` (`HOST_A`) runs the NFS service while it is up and `server02` (`HOST_B`) takes over only in case of failure of `server01`, hence some of the assignments for `server02` below are empty.

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
# The high speed network interface for NFS traffic, used for the floating IP address
FLOATING_INTERFACES_HOST_A=("ib0")
FLOATING_INTERFACES_HOST_B=()
# The floating IP address that will be moved to HOST_B in case HOST_A fails
FLOATING_IPADDRS_HOST_A=("192.168.0.1/24")
FLOATING_IPADDRS_HOST_B=()
# The NVMesh volume that will be attached to HOST_B in case HOST_A fails
NVMESHVOLS_HOST_A=("nfsvolume")
NVMESHVOLS_HOST_B=()
# The mountpoint that will be used on HOST_B in case HOST_A fails
MOUNTPOINTS_HOST_A=("/mnt/nfsexport")
MOUNTPOINTS_HOST_B=()
# The name of the systemd service to run on HOST_B in case HOST_A fails
SERVICES_HOST_A=("nfs-server")
SERVICES_HOST_B=()
```

### Configure nvkeep fstab

nvkeep uses a separate fstab for its mountpoints, which has the same syntax as the normal `/etc/fstab`. Start by copying the fstab from the empty template file on `server01`:

```bash
cp /etc/nvkeep/fstab.TEMPLATE /etc/nvkeep/fstab
```

Now fill in the mountpoint info for our nvkeep-protected NFS service by editing `/etc/nvkeep/fstab` using your favorite text editor:

```
/dev/nvmesh/nfsvolume  /mnt/nfsexport  xfs  defaults  0 0
```

## Apply nvkeep config

Running the `nvkeep_appy_config` tool on `server01` (`HOST_A`) will create the `/etc/keepalived.conf` file on both servers and copy the `nvkeep_service.conf` and nvkeep `fstab` to `server02` (`HOST_B`) via `ssh`/`scp`:

``` bash
nvkeep_apply_config
```

## Starting the nvkeep-protected NFS Service

When you run the keepalived service now on `server01`, it will become the master for the configured service and bring up all configured resources:

```
server01: systemctl restart keepalived
```

You can now confirm that everything is up and running as intended by using the `nvkeep_check_status` tool on `server01`. (It might take a few seconds until everything is up.)

```bash
server01: nvkeep_check_status -l

[OK] VOLUME: nfsvolume
[OK] MOUNTPOINT: /mnt/nfsexport
[OK] FLOATING IP: ib0 192.168.0.1/24
[OK] SERVICE: nfs-server
```

If something is not ok, you can find keepalived log messages in syslog (`/var/log/messages`), the events delivered by keepalived to nvkeep in `/var/log/nvkeep/event_handler.log` and the corresponding actions based on received events in `/var/log/nvkeep/actions.log`.

When everyting looks good, proceed by running keepalived on `server02`:

```bash
server02: systemctl restart keepalived
```

## Mounting the NFS client

The server side is up and running, so now it's time to connect our NFS client. Run the following command on `client01` to mount NFS using the floating IP address of the servers:

```bash
yum install nfs-utils
mkdir /mnt/nfs

mount.nfs -o vers=3 192.168.0.1:/mnt/nfsexport /mnt/nfs
```

## Simulating Server Failure

The easiest way to test what happens in case of server failure is to shutdown the resources on `server01` and stop keepalived:

```bash
server01: nvkeep_clean_shutdown
```

The `nvkeep_check_status` command on `server02` will show you that the failover happens within a couple of seconds. It takes about 1 minute for the NFS client to retry the connection and resume its normal operation.

```bash
server02: nvkeep_check_status -p

[OK] VOLUME: nfsvolume
[OK] MOUNTPOINT: /mnt/nfsexport
[OK] FLOATING IP: ib0 192.168.150.1/24
[OK] SERVICE: nfs-server
```

After verifying that the failover worked as expected, bring back everything to normal on `server01` by simply restarting its keepalived service:

```bash
server01: systemctl restart keepalived
```

## Additional Notes: Keepalived Autostart or not

Make sure to check the additional notes section about `keepalived` autostart on system boot in the [readme](../README.md).
