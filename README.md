# btrBackup

A "simple" tcl script for local backups (e.g. to external harddrives) when source and
target filesystem are both btrfs filesystems.

# Requirements

You need
- tcl
- rsync
- btrfs-progs

# Installation

Copy btrbackup.tcl into a directory in your PATH, e.g. /usr/bin, and btrbackupconfig.tcl
into /etc. If you use Arch Linux you can use the PKGBUILD file to create a package.

# Backup Preparations

You need to setup mountpoints for the root subvolume in your fstab for both source and
target filesystem. The mountpoints need to be "noauto" in fstab - they are mounted
during backup. You need to create subvolumes on your target filesystem to sync your
files to. For each target subvolume you need to create a directory for storing snapshots
of it.

The example configuration assumes the following setup:

A btrfs partition with subvolumes "root-subvol", "var-subvol" and "boot-subvol"
for "/", "/var" and "/boot" and mountpoint "/mnt/root-filesystem" in fstab.
A btrfs partition with a subvolume "home-subvol" for "/home" and mountpoint
"/mnt/home-filesystem" in fstab.

An external harddrive with subvolumes "backup-root" and "backup-home" and mountpoint
"/mnt/backup". The filesystem contains two directories (or subvolumes) "snapshots-root"
and "snapshots-home".

So fstab might contain something like:

    # system
    LABEL=ssd-btr    /                    btrfs    subvol=root-subvol,compress=lzo   0 0
    LABEL=ssd-btr    /boot                btrfs    subvol=boot-subvol                0 0
    LABEL=ssd-btr    /var                 btrfs    subvol=var-subvol                 0 0
    LABEL=hd-btr     /home                btrfs    subvol=home-subvol                0 0

    # backup
    LABEL=ssd-btr    /mnt/root-filesystem btrfs    noauto                            0 0
    LABEL=hd-btr     /mnt/home-filesystem btrfs    noauto                            0 0
    LABEL=backup-hd  /mnt/backup          btrfs    noauto                            0 0

# Configuration

An example configuration is given in btrbackupconfig.tcl which is assumed to reside
in "/etc". You have one section with expire-rules (inpsired by the backup-tool dirvish).
There you specify rules for the backup target snapshot to keep. Other snapshots will be
deleted at the beginning of a backup run.

In the example configuration only the most current versions of the root-snapshots are
kept. Snapshots of the "/home"-backup have a somewhat more complex keeping-ruleset:
- Keep the first one of every year.
- Keep the first one of every of the last 12 months.
- Keep everything of the last 30 days.
- Keep the last 3 snapshots.

Then comes the backup setup. You can setup multiple backup targets. For each target
you need to specify its mountpoint and its target subvolumes with snapshot-directory
and expire ruleset.

Then you specify syncrules containing a source mountpoint, a source subvolume, the
target subvolume with a relative path and directories to exclude for rsync (they will
be extended by "/\*\*".

Each target setup has a name by which it can be run later.

# Running Backups

With the example configuration and setup you could simply run:

    $ btrbackup.tcl my_backup

You might also want to run somthing like:

    $ btrbackup.tcl my_backup | tee backuplog.log

