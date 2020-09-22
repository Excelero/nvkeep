# nvkeep

**Keep linux services alive on server failures, based on protected NVMesh volumes**

nvkeep is an easy to use linux service high availability (HA) framework that can keep any linux service alive in case of server failure. To do this, it creates a scenario which looks to clients on the network like the original server would still be up and running, even though nvkeep has actually moved the protected service to a backup host.

An nvkeep-protected service can be an NFS export, a BeeGFS service, a database server like MySQL or any other systemd-based linux service.

## Server Failure Detection and Failover

Whether a physical server is still up is detected by a lightweight service named [keepalived](https://github.com/acassen/keepalived), which comes with all major Linux distributions. nvkeep includes tools to easily configure keepalived, to monitor the status of the system and to automatically trigger the following actions in case the primary server for a nvkeep-protected Linux service fails:

1. Exclusively attach the underlying NVMesh volume of the nvkeep-protected service to the backup host. (Exclusive attachment ensures split brain safety from the storage perspective.)
2. Mount the file system of the nvkeep-protected service on the backup host.
3. Move the floating IP address of the nvkeep-protected service to the backup host.
4. Start the nvkeep-protected service on the backup host.

After this, the nvkeep-protected service is available under its original IP address to the network clients and has access to all its data on the NVMesh volume.

## Installation

### Prerequisites

nvkeep requires keepalived v1.3.6 or higher, which is included in RHEL/CentOS 8.0 and higher and in Ubuntu 18.04 and higher.

#### Install keepalived on Ubuntu 18.04 or higher

```bash
apt install keepalived
```

#### Install keepalived on RHEL/CentOS 8.0 or higher

```bash
yum install keepalived
```

#### Install keepalived on RHEL/CentOS 7.x

The version of keepalived included in RHEL/CentOS 7.x is too old, but it's easy to install a newer version from the official webiste. The official install guide is available [here](https://github.com/acassen/keepalived/blob/master/INSTALL). These are the steps:

```bash
yum -y install autoconf automake git openssl-devel libnl3-devel ipset-devel
git clone https://github.com/acassen/keepalived.git
cd keepalived
git checkout v2.1.5
./build_setup
./configure
mkdir -p ~/rpmbuild/SOURCES
make rpm
# install created rpm
cd $(rpm --eval "%{_rpmdir}")/x86_64
yum install keepalived-2.1.5-1.el7.x86_64.rpm
```

### Install nvkeep

```bash
git clone https://github.com/Excelero/nvkeep.git
cd nvkeep
```

**For RHEL/CentOS:**

```bash
./create_rpm_package.sh
yum -y install ./packaging/RPMS/noarch/nvkeep*.rpm
```

**For Ubuntu:**

```bash
./create_deb_package.sh
apt -y install ./packaging/nvkeep*.deb
```

Afterwards, the `nvkeep_apply_config` command will guide you through the setup process. 

### Configuration Walk-Through Examples

- Setting up a highly available NFS server with nvkeep: See [here](doc/Example-NFS.md)
- Setting up a highly available BeeGFS file system with nvkeep: See [here](doc/Example-BeeGFS.md)

## Status Monitoring & Management

All nvkeep tools have a built-in help, which can be viewed by using the `-h` argument.

### Monitoring

The `nvkeep_check_status` command will check if all services which run preferably on the current host, are actually running and also whether any services that run preferably on its peer host, are currently running.

In this example, all hosts are up and running, so host `server01`, which is configured as a highly available NFS server, reports that all its services are OK:

```bash
server01: nvkeep_check_status -l

[OK] VOLUME: nfsvolume
[OK] MOUNTPOINT: /mnt/nfsexport
[OK] FLOATING IP: ib0 192.168.150.1/24
[OK] SERVICE: nfs-server
```

#### Log files

- Keepalived log messages are included in the normal system log, e.g. `/var/log/messages`
- Events (such as a host becoming the master for a nvkeep-protected service) are in `/var/log/nvkeep/event_handler.log`
- Actions that are taken by nvkeep based on received events are in `/var/log/nvkeep/actions.log`

### Management

Most of the time, you will just have the `keepalived` service running and sleep well at night, knowing that `keepalived` and `nvkeep` ensure your services are running. However, there might be situations where you briefly want to restart the nvkeep-protected service without going through the full failover and failback procedure. This could be the case after you updated a service package to the latest version and now just want to restart it.

#### Manual Service Restart after Service Package Update

It's no problem to just manually restart an nvkeep-protected service like you would usually do without `nvkeep`. For example, if the nvkeep-protected service is an nfs-server, then you could do it just like this:

```bash
server01: systemctl restart nfs-server
```

#### Clean Service Shutdown before Server Reboot

If you ran a full OS update and now would like to reboot the host `server01`, it's best to do a graceful service shutdown that allows a clean unmount of the underlying file system and then afterwards stop `keepalived` to trigger a failover to the other host.

First let's disable keepalived automatic start on boot to prevent immediate failback after reboot:

```bash
server01: systemctl disable keepalived
```

Now we do a clean shutdown of the nvkeep-protected service and associated resources:

```bash
server01: nvkeep_clean_shutdown -l
Stopping localhost preferred services and associated resources...
All done.
```

Then we stop keepalived to trigger the failover to the backup host and reboot the server:

```
server01: systemctl stop keepalived
server01: reboot
```

When `server01` is back up, we do a clean shutdown of its resources on the backup host (`server02`) and then start `keepalived` again to trigger the failback to `server01`:

```bash
server02: nvkeep_clean_shutdown -p
Stopping localhost preferred services and associated resources...
All done.

server01: systemctl start keepalived
server01: systemctl enable keepalived
```

That's it. You can now use the `nvkeep_check_status` command to confirm that everything is back to normal state.

## Additional Notes: Keepalived Autostart or not

Enabling `keepalived` autostart on system boot will ensure that all nvkeep-protected services come up automatically again after a server failure. However, a server failure also means that something is broken and might need repair before resuming normal operation.

Thus, it is recommended to disable autostart of keepalived, so that you can analyze what lead to the server failure before starting keepalived and the associated nvkeep-protected services again on this host:

```bash
server01: systemctl disable keepalived
server02: systemctl disable keepalived
```

