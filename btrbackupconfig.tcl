#####################################
### btrbackup example config file ###
#####################################

######################
### Expire Rules   ###
######################

btrbackup::new_expire_ruleset "expire-home"

# add rules - examples:
# -> keep all snapshots of the last 30 days
btrbackup::add_expire_rule alloflastdays 30

# -> keep first snapshot of every year
btrbackup::add_expire_rule firstofyear "all"

# -> keep first snapshot of last 12 moths
btrbackup::add_expire_rule firstofmonth 12

# -> keep last 3 snapshots - whenever they were created
btrbackup::add_expire_rule last 3

# commit this ruleset
# -> keep one snapshot of every year, one of every month of the last 12 months,
#    all snapshots of the last 30 days and every one of the last 3 snapshots
btrbackup::commit_expire_ruleset


# and another ruleset for root bacukp
btrbackup::new_expire_ruleset "expire-root"
btrbackup::add_expire_rule last 3
btrbackup::add_expire_rule alloflastdays 20
btrbackup::commit_expire_ruleset


######################
### Backup Targets ###
######################

# create new config for a backup target drive
# -> chose an arbitrary name
btrbackup::new_config "my_backup"

# mountpoint
# -> you need an appropriate entry in your /etc/fstab so that
#    mount /mnt/backup
#    or whatever mountpoint you specify here will work
#    the filesystem needs to be btrfs of course!
btrbackup::mountpoint "/mnt/backup"

# subvolumes to use on target, path to use for snapshots and expire ruleset to use for cleanup
# -> specify one or more subvolumes to copy files to and a directory 
#    to create snapshots of them in and expire rules for deleting snapshots
#    in the example there will be a subvolume in /mnt/backup/backup-root
#    and one in /mnt/backup/backup-home ... snapshots of the first will be
#    created in  /mnt/backup/snapshots-root/ and so on.
#    both the initial subvolumes and the snapshot directories need to be prepared
#    before. Expire rules need to be defined above.
btrbackup::add_target_subvol "backup-root" "snapshots-root" "expire-root"
btrbackup::add_target_subvol "backup-home" "snapshots-home" "expire-home"

# synp-rules: mountpoint for source volume root, source subvolumes, target subvolumes, target subdirectory, list of directories to exclude
# -> create rules for subvolumes to be synced. The first parameter is the mountpoint (again: must already be specified in /etc/fstab) of the
#    source filesystem (must of course be btrfs), The second parameter is the subvolume to be synced - a snapshot of this subvolume
#    will be created temporarily as backup source. The third parameter is the target subvolume (one of the ones specified above) to sync
#    to, the fourth parameter is the path to a directory in the target subvolume - e.g.: the second sync-rule syncs /mnt/root-filesystem/boot-subvol
#    to /mnt/backup/backup-root/boot. The fifth parameter is a list of exclude rules (in general you can use everything rsync accepts after
#    the --exclude option. You should exclude subdirectories you later on sync to from a separate source like in the example.
btrbackup::add_sync_rule "/mnt/root-filesystem" "root-subvol" "backup-root" ""      {"boot" "var"}
btrbackup::add_sync_rule "/mnt/root-filesystem" "boot-subvol" "backup-root" "/boot" {}
btrbackup::add_sync_rule "/mnt/root-filesystem" "var-subvol"  "backup-root" "/var"  {}
btrbackup::add_sync_rule "/mnt/home-filesystem" "home-subvol" "backup-home" ""      {}

# commit config for this backup target
# -> if you have multiple drives to sync to you can add the next one after this, starting again
#    with btrbackup::new_config ... and finish with btrbackup::commit_config.
btrbackup::commit_config

# -> now you can just run btrbackup.tcl my_backup_medium and synchronization will start
