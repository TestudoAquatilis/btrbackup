#!/usr/bin/tclsh

##
##    btrbackup: A tcl script solution for local backups from btrfs filesystems
##    to btrfs filesystems using rsync, inspired by dirvish
##    Copyright (C) 2015 Andreas Dixius
##
##    This program is free software: you can redistribute it and/or modify
##    it under the terms of the GNU General Public License as published by
##    the Free Software Foundation, either version 3 of the License, or
##    (at your option) any later version.
##
##    This program is distributed in the hope that it will be useful,
##    but WITHOUT ANY WARRANTY; without even the implied warranty of
##    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
##    GNU General Public License for more details.
##
##    You should have received a copy of the GNU General Public License
##    along with this program.  If not, see <http://www.gnu.org/licenses/>.
##

namespace eval btrbackup {
	##########################
	## configuration        ##
	##########################
	namespace eval config {
		# temporary storage for config information
		namespace eval current {
			set name ""
			set name_valid "false"

			set mountpoint ""
			set mountpoint_valid "false"

			set target_list {}
			set target_list_valid "false"

			set sync_rules {}
			set sync_rules_valid "false"
		}

		set config_error "false"
		# list of all config data
		set config_list {}

		# commit current configuration
		proc commit {} {
			variable config_error
			variable config_list

			if {! $current::name_valid} {
				set config_error "true"
				puts "Error: no valid config-name set."
			}
			if {! $current::mountpoint_valid} {
				set config_error "true"
				puts "Error: no valid target mountpoint configured for $current::name."
			}
			if {! $current::target_list_valid} {
				set config_error "true"
				puts "Error: no valid target subvolumes configured for $current::name."
			}
			if {! $current::sync_rules_valid} {
				set config_error "true"
				puts "Error: no sync rules configured for $current::name."
			}


			lappend config_list [list $current::name $current::mountpoint $current::target_list $current::sync_rules]

			set current::name ""
			set current::name_valid "false"
			set current::mountpoint ""
			set current::mountpoint_valid "false"
			set current::target_list {}
			set current::target_list_valid "false"
			set current::sync_rules {}
			set current::sync_rules_valid "false"
		}
	}

	namespace eval expireconfig {
		namespace eval current {
			set name ""
			set name_valid "false"

			set rules {}
			set rules_valid "false"
		}

		set config_error "false"
		set config_list {}

		# commit current configuration
		proc commit {} {
			variable config_error
			variable config_list

			if {! $current::name_valid} {
				set config_error "true"
				puts "Error: no valid expire-ruleset-name set."
			}

			if {! $current::rules_valid} {
				set config_error "true"
				puts "Error: no expire rules configured for $current::name."
			}

			lappend config_list [list $current::name $current::rules]

			set current::name ""
			set current::name_valid "false"
			set current::rules {}
			set current::rules_valid "false"
		}
	}

	### expire rule configuration
	proc new_expire_ruleset {name} {
		if {$name == ""} {
			puts "Error: ruleset-name must be non-empty."
			set expireconfig::config_error "true"
			return
		}
		if {$expireconfig::current::name_valid} {
			puts "Error: expire ruleset $current::name not yet committed."
			set expireconfig::config_error "true"
			return
		}
		set expireconfig::current::name $name
		set expireconfig::current::name_valid "true"
	}

	proc add_expire_rule {rule parameter} {
		if {[llength [info procs "expire::rules::$rule"]] < 1} {
			puts "Error: expire rule $rule does not exist"
			set expireconfig::config_error "true"
			return
		}

		if {!([string is integer $parameter] || $parameter == "all")} {
			puts "Error: expire rule parameter must be \"all\" or a number"
			set expireconfig::config_error "true"
			return
		}

		lappend expireconfig::current::rules [list $rule $parameter]
		set expireconfig::current::rules_valid "true"
	}

	proc commit_expire_ruleset {} {
		expireconfig::commit
	}

	### backup target configuration
	proc new_config {name} {
		if {$name == ""} {
			puts "Error: config-name must be non-empty."
			set config::config_error "true"
			return
		}
		if {$config::current::name_valid} {
			puts "Error: config $current::name not yet committed."
			set config::config_error "true"
			return
		}
		set config::current::name $name
		set config::current::name_valid "true"
	}

	proc mountpoint {value} {
		if {![file exists $value]} {
			puts "Error: mountpoint $value does not exist."
			set config::config_error "true"
			return
		}
		set config::current::mountpoint $value
		set config::current::mountpoint_valid "true"
	}

	proc add_target_subvol {subvol snapshot_dir expire_ruleset} {
		if {$subvol == ""} {
			puts "Error: subvol-name must be non-empty."
			set config::config_error "true"
			return
		}
		if {[lsearch -index 0 $expireconfig::config_list $expire_ruleset] < 0} {
			puts "Error: $expire_ruleset is no valid expire-ruleset"
			set config::config_error "true"
			return
		}

		lappend config::current::target_list $subvol $snapshot_dir $expire_ruleset
		set config::current::target_list_valid "true"
	}

	proc add_sync_rule {src_mountpoint src_subvol target_subvol target_subdir exclude_list} {
		if {$src_mountpoint == ""} {
			puts "Error: source-mointpoint must be non-empty."
			set config::config_error "true"
			return
		}
		if {$src_subvol == ""} {
			puts "Error: source-subvolume must be non-empty."
			set config::config_error "true"
			return
		}
		if {$target_subvol == ""} {
			puts "Error: target-subvolume must be non-empty."
			set config::config_error "true"
			return
		}

		if {[expr [lsearch $config::current::target_list $target_subvol] % 3] != 0} {
			puts "Error: target-subvolume $target_subvol is not configured in current target-list."
			set config::config_error "true"
			return
		}
		if {[expr [lsearch $config::current::sync_rules $src_mountpoint] % 2] != 0} {
			lappend config::current::sync_rules $src_mountpoint {}
		}

		set i_current [expr [lsearch $config::current::sync_rules $src_mountpoint] + 1]
		set new_synclist [linsert [lindex $config::current::sync_rules $i_current] end $src_subvol $target_subvol $target_subdir $exclude_list]
		set config::current::sync_rules [lreplace $config::current::sync_rules $i_current $i_current $new_synclist]

		set config::current::sync_rules_valid "true"
	}

	proc commit_config {} {
		config::commit
	}

	############################
	## Expire rules and run   ##
	############################
	namespace eval expire {
		namespace eval rules {
			# expire rules: taking an argument and a sorted list of dates, returning a list of dates to keep
			proc last {n datelist} {
				if {[llength $datelist] < 1} {
					return {}
				}

				if {$n >= $datelist} {
					return $datelist
				}

				set startrange [expr [llength $datelist] - $n]

				return [lrange $datelist $startrange end]
			}

			proc firstofyear {n datelist} {
				if {[llength $datelist] < 1} {
					return {}
				}

				set startyear [expr [lindex $datelist 0 0] - 1]

				if {$n != "all"} {
					set startyear [expr [clock format [clock seconds] -format "%Y"] - $n]
				}

				set currentyear $startyear

				set result {}

				foreach i_date $datelist {
					if {[lindex $i_date 0] > $currentyear} {
						lappend result $i_date
						set currentyear [lindex $i_date 0]
					}
				}

				return $result
			}

			proc firstofmonth {n datelist} {
				if {[llength $datelist] < 1} {
					return {}
				}

				set startyear  [expr [lindex $datelist 0 0]]
				set startmonth 0

				if {$n != "all"} {
					set startyear  [expr [clock format [clock seconds] -format "%Y"]]
					set startmonth [expr [clock format [clock seconds] -format "%m"] - $n]

					while {$startmonth < 0} {
						set startyear  [expr $startyear - 1]
						set startmonth [expr $startmonth + 12]
					}
				}

				set currentyear  $startyear
				set currentmonth $startmonth

				set result {}

				foreach i_date $datelist {
					if {[lindex $i_date 0] > $currentyear} {
						lappend result $i_date
						set currentyear [lindex $i_date 0]
						set currentmonth [lindex $i_date 1]
					} elseif {[lindex $i_date 0] == $currentyear && [lindex $i_date 1] > $currentmonth} {
						lappend result $i_date
						set currentmonth [lindex $i_date 1]
					}
				}

				return $result
			}

			proc alloflastdays {n datelist} {
				if {[llength $datelist] < 1} {
					return {}
				}

				set target_date [expr [clock seconds] - $n * 3600 * 24]
				set startyear  [expr [clock format $target_date -format "%Y"]]
				set startmonth [expr [clock format $target_date -format "%m"]]
				set startday   [expr [clock format $target_date -format "%d"]]

				set found "false"
				set result {}

				foreach i_date $datelist {
					if {!$found} {
						if {[lindex $i_date 0] > $startyear} {
							set found "true"
						} elseif {([lindex $i_date 0] == $startyear) && ([lindex $i_date 1] > $startmonth)} {
							set found "true"
						} elseif {([lindex $i_date 0] == $startyear) && ([lindex $i_date 1] == $startmonth) && ([lindex $i_date 2] >= $startday)} {
							set found "true"
						}
					}

					if {$found} {
						lappend result $i_date
					}
				}

				return $result
			}
		}

		proc get_expire_list {datelist rulelist} {
			set rmlist $datelist

			foreach i_rule $rulelist {
				set keeplist [rules::[lindex $i_rule 0] [lindex $i_rule 1] $datelist]
				#puts "keeplist: $keeplist"

				set new_rmlist {}

				foreach i_rmitem $rmlist {
					if {[lsearch $keeplist $i_rmitem] < 0} {
						lappend new_rmlist $i_rmitem
					}
				}

				#puts "new rmlist: $new_rmlist"

				set rmlist $new_rmlist
			}

			return $rmlist
		}

		### suppress execution for debugging
 		#proc exec args {
 		#	puts $args
 		#	if {[expr int(rand() * 100)] > 93} {
 		#		#error bla
 		#	}
 		#}

		proc expire_snapshot_dir {nameprefix rulelist} {
			set date_snapshot_list {}
			set date_list {}

			# create lists
			set re "${nameprefix}(\[0-9\]+)-(\[0-9\]+)-(\[0-9\]+)_(\[0-9\]+)-(\[0-9\]+)"
			foreach i_snapshot [glob "${nameprefix}*"] {
				if {[regexp $re $i_snapshot full year month day hour minute]} {
					set date [list $year $month $day $hour $minute]
					lappend date_list $date
					lappend date_snapshot_list [list $date $i_snapshot]
				}
			}

			# expire list
			set expire_dates [get_expire_list $date_list $rulelist]

			# remove expired
			foreach i_date $expire_dates {
				set ds_idx [lsearch -index 0 $date_snapshot_list $i_date]
				set i_snapshot [lindex $date_snapshot_list $ds_idx 1]

				puts "INFO: deleting snapshot $i_snapshot"

				if {[catch {exec btrfs subvolume delete "${i_snapshot}"} data]} {
					puts "ERROR: failed to delete snapshot $i_snapshot"
					puts $data
					return "false"
				}
			}

			return "true"
		}
	}



	##########################
	## Backup Execution     ##
	##########################
	namespace eval run {
		set src_snapshot_prefix "bckp-snp-"
		set rsyn_opts [list "-axsv" "--delete"]

		### suppress execution for debugging
 		#proc exec args {
 		#	puts $args
 		#	if {[expr int(rand() * 100)] > 93} {
 		#		#error bla
 		#	}
 		#}

		proc create_src_snapshots_from_list {fs_mountpoint snapshot_list snapshot_prefix} {
			if {[llength $snapshot_list] <= 0} {
				return "true"
			}

			set current_subvol [lindex $snapshot_list 0]
			set remaining_list [lreplace $snapshot_list 0 0]

			cd $fs_mountpoint

			if {[catch {exec btrfs subvolume snapshot $current_subvol "${snapshot_prefix}${current_subvol}"} data]} {
				puts "ERROR: failed to create snapshot of $current_subvol in ${snapshot_prefix}${current_subvol}"
				puts $data
				return "false"
			} else {
				puts "INFO: created snapshot of $current_subvol in ${snapshot_prefix}${current_subvol}"
			}

			if {[create_src_snapshots_from_list $fs_mountpoint $remaining_list $snapshot_prefix]} {
				return "true"
			} else {
				cd $fs_mountpoint
				if {[catch {exec btrfs subvolume delete "${snapshot_prefix}${current_subvol}"} data]} {
					puts "ERROR: failed to delete snapshot ${snapshot_prefix}${current_subvol} of $current_subvol"
					puts $data
				} else {
					puts "INFO: deleted snapshot ${snapshot_prefix}${current_subvol} of $current_subvol"
				}
				return "false"
			}
		}

		proc prepare_src_snapshots {backup_src_list snapshot_prefix} {
			if {[llength $backup_src_list] <= 1} {
				return "true"
			}

			set current_mountpoint [lindex $backup_src_list 0]
			set current_srclist    [lindex $backup_src_list 1]

			set snapshot_list {}
			foreach {subvol target dir excl} $current_srclist {
				lappend snapshot_list $subvol
			}

			if {[catch {exec mount $current_mountpoint} data]} {
				puts "ERROR: failed to mount $current_mountpoint"
				puts $data
				return "false"
			} else {
				puts "INFO: mounted $current_mountpoint"
			}

			set result "true"

			if {[create_src_snapshots_from_list $current_mountpoint $snapshot_list $snapshot_prefix]} {
				set result [prepare_src_snapshots [lreplace $backup_src_list 0 1] $snapshot_prefix]

				if {! $result} {
					cleanup_src_snapshots_from_list $current_mountpoint $snapshot_list $snapshot_prefix
				}
			} else {
				set result "false"
			}

			if {! $result} {
				cd /
				exec sleep 10
				if {[catch {exec umount $current_mountpoint} data]} {
					puts "ERROR: failed to umount $current_mountpoint"
					puts $data
				} else {
					puts "INFO: umounted $current_mountpoint"
				}
			}

			return $result
		}

		proc cleanup_src_snapshots_from_list {fs_mountpoint snapshot_list snapshot_prefix} {
			if {[llength $snapshot_list] <= 0} {
				return "true"
			}

			set current_subvol [lindex $snapshot_list 0]
			set remaining_list [lreplace $snapshot_list 0 0]

			set result "true"

			if {[cleanup_src_snapshots_from_list $fs_mountpoint $remaining_list $snapshot_prefix]} {
				set result "true"
			} else {
				set result "false"
			}

			cd $fs_mountpoint

			if {[catch {exec btrfs subvolume delete "${snapshot_prefix}${current_subvol}"} data]} {
				puts "ERROR: failed to delete snapshot ${snapshot_prefix}${current_subvol} of $current_subvol"
				puts $data
				return "false"
			} else {
				puts "INFO: deleted snapshot ${snapshot_prefix}${current_subvol} of $current_subvol"
			}

			return $result
		}

		proc cleanup_src_snapshots {backup_src_list snapshot_prefix} {
			if {[llength $backup_src_list] <= 1} {
				return "true"
			}

			set current_mountpoint [lindex $backup_src_list 0]
			set current_srclist    [lindex $backup_src_list 1]

			set snapshot_list {}
			foreach {subvol target dir excl} $current_srclist {
				lappend snapshot_list $subvol
			}

			set result "true"

			if {! [cleanup_src_snapshots_from_list $current_mountpoint $snapshot_list $snapshot_prefix]} {
				set result "false"
			}

			cd /
			exec sleep 10
			if {[catch {exec umount $current_mountpoint} data]} {
				puts "ERROR: failed to umount $current_mountpoint"
				puts $data
				set result "false"
			} else {
				puts "INFO: umounted $current_mountpoint"
			}

			if {! [cleanup_src_snapshots [lreplace $backup_src_list 0 1] $snapshot_prefix]} {
				set result "false"
			}

			return $result
		}

		# syncing
		proc stage2_sync {target_mountpoint src_list snapshot_prefix} {
			variable rsyn_opts
			set result "true"

			foreach {i_src_mnt i_syn_list} $src_list {
				foreach {j_src_vol j_target_vol j_target_subdir j_excludes} $i_syn_list {
					set cur_srcdir "${i_src_mnt}/${snapshot_prefix}${j_src_vol}"
					set cur_tardir "${target_mountpoint}/${j_target_vol}${j_target_subdir}"

					set cur_cmd [list "rsync"]

					foreach opt $rsyn_opts {
						lappend cur_cmd $opt
					}

					foreach excl $j_excludes {
						lappend cur_cmd "--exclude"
						lappend cur_cmd "${excl}/**"
					}

					lappend cur_cmd "${cur_srcdir}/"
					lappend cur_cmd "${cur_tardir}"

					puts "INFO: syncing volume $j_src_vol"
					if {[catch {eval exec $cur_cmd} data]} {
						puts $data
						puts "ERROR: failed to sync $cur_srcdir to $cur_tardir"
						set result "false"
					} else {
						puts $data
						puts "INFO: synced $cur_srcdir to $cur_tardir"
					}

					if {! $result} {
						break
					}
				}

				if {! $result} {
					break
				}
			}

			return $result
		}

		# target snapshotting
		proc stage2_snapshots {target_mountpoint target_list} {
			set result "true"
			set date_suffix [clock format [clock seconds] -format "%Y-%m-%d_%H-%M"]

			foreach {i_vol i_dir i_exprule} $target_list {
				cd $target_mountpoint

				if {[catch {exec btrfs subvolume snapshot "$i_vol" "${i_dir}/${i_vol}-${date_suffix}"} data]} {
					puts "ERROR: could not create snapshot of $i_vol"
					puts $data
					set result "false"
				} else {
					puts "INFO: created snapshot of $i_vol"
				}
			}

			return $result
		}

		# src snapshot handling
		proc stage1 {target_mountpoint target_list src_list snapshot_prefix} {
			set result "true"

			if {! [prepare_src_snapshots $src_list $snapshot_prefix]} {
				return "false"
			}

			if {! [stage2_sync $target_mountpoint $src_list $snapshot_prefix]} {
				set result "false"
			}

			if {$result} {
				if {! [stage2_snapshots $target_mountpoint $target_list]} {
					set result "false"
				}
			}

			if {! [cleanup_src_snapshots $src_list $snapshot_prefix]} {
				set result "false"
			}

			return $result
		}

		# expire
		proc expire_target {subvolume snapshot_dir expire_ruleset} {
			puts "INFO: deleting expired snapshots of subvolume $subvolume"
			cd $snapshot_dir

			set ruleset_index [lsearch -index 0 [set "[namespace parent]::expireconfig::config_list"] $expire_ruleset]
			if {$ruleset_index < 0} {
				puts "ERROR: could not find expire-ruleset $expire_ruleset"
				return "false"
			}

			set ruleset [lindex [set "[namespace parent]::expireconfig::config_list"] $ruleset_index 1]

			return [[namespace parent]::expire::expire_snapshot_dir "$subvolume-" $ruleset]
		}

		proc expire_run {target_mountpoint target_list} {

			foreach {i_vol i_dir i_exprule} $target_list {
				if {! [expire_target $i_vol "${target_mountpoint}/$i_dir" $i_exprule]} {
					puts "ERROR: failed to delete expired snapshotfs of $i_vol"
					return "false"
				}
			}

			return "true"
		}

		# target mounting and umounting
		proc stage0 {target_mountpoint target_list src_list} {
			variable src_snapshot_prefix

			set result "true"

			if {[catch {exec mount $target_mountpoint} data]} {
				puts "ERROR: failed to mount $target_mountpoint"
				puts $data
				return "false"
			} else {
				puts "INFO: mounted target $target_mountpoint"
			}


			if {![expire_run $target_mountpoint $target_list]} {
				set result "false"
			}

			if {$result} {
				if {![stage1 $target_mountpoint $target_list $src_list $src_snapshot_prefix]} {
					set result "false"
				}
			}

			cd /
			exec sleep 10
			if {[catch {exec umount $target_mountpoint} data]} {
				puts "ERROR: failed to umount $target_mountpoint"
				puts $data
				return "false"
			} else {
				puts "INFO: umounted target $target_mountpoint"
				return $result
			}

		}

	}

	proc help {} {
		puts "btrbackup - a simple script solution for btrfs backup handling"
		puts "execution: $::argv0 <target>"
		puts "available targets are:"

		foreach i_conf $config::config_list {
			puts " - [lindex $i_conf 0]"
		}
	}

	proc run_backup {} {
		if {$::argc != 1} {
			puts "ERROR: need exactly 1 argument: name of backup configuration to run"
			puts ""
			help
			return "false"
		}

		set config_to_use [lindex $::argv 0]

		if {$config_to_use == "-h" || $config_to_use == "--help"} {
			help
			return "true"
		}

		if {$config::config_error} {
			puts "ERROR: invalid configuration"
			return "false"
		}

		if {[lsearch -index 0 $config::config_list $config_to_use] < 0} {
			puts "ERROR: config $config_to_use not found."
			puts ""
			help
			return "false"
		}

		set config_data [lindex $config::config_list [lsearch -index 0 $config::config_list $config_to_use]]

		set target_mountpoint [lindex $config_data 1]
		set target_list       [lindex $config_data 2]
		set src_list          [lindex $config_data 3]
		set result [run::stage0 $target_mountpoint $target_list $src_list]

		if {$result} {
			puts "INFO: backup ran successfully"
		} else {
			puts "Errors occured"
		}
	}
}


## read in configuration data and execute backup
source "/etc/btrbackupconfig.tcl"

btrbackup::run_backup

