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


namespace eval log {
	### logging...

	# indentation
	variable log_tab ""

	# initial log level
	if {![info exists log_level]} {
		variable log_level 0
	}

	# initial maximum line length
	if {![info exists max_line]} {
		variable max_line 1024
	}

	variable section_line 100

	# set loglevel hard
	proc set_log_level {{level "INFO"}} {
		variable log_level

		switch $level {
			"DEBUG"   {set log_level 0}
			"INFO"    {set log_level 1}
			"WARNING" {set log_level 2}
			"ERROR"   {set log_level 3}
		}
	}

	# temporarily switch loglevels
	variable loglevel_stack {}

	proc switch_log_level {level} {
		variable loglevel_stack
		variable log_level

		lappend loglevel_stack $log_level
		set_log_level $level
	}

	proc reset_log_level {} {
		variable loglevel_stack
		variable log_level

		if {[llength $loglevel_stack] >= 1} {
			set log_level [lindex $loglevel_stack end]

			set loglevel_stack [lrange $loglevel_stack 0 end-1]
		}
	}

	# actual logging
	proc log_debug   {msg} {log $msg "DEBUG:  " 0}
	proc log_info    {msg} {log $msg "INFO:   " 1}
	proc log_warning {msg} {log $msg "WARNING:" 2}
	proc log_error   {msg} {log $msg "ERROR:  " 3}

	proc log {msg {prefix "INFO:   "} {severity 1}} {
		variable log_tab
		variable log_level
		variable max_line

		if {$log_level <= $severity} {
			if {[string length $msg] <= $max_line} {
				log_output "${prefix}${log_tab}${msg}"
			} else {
				## shorten if too long...
				set msg_rem $msg

				set lnum 0

				while {[string length $msg_rem] > $max_line} {
					## cut point
					set index_s [string first " " $msg_rem]
					set index_temp_s 0
					while {$index_s >= 0 && $index_s < $max_line && $index_temp_s >= 0 && $index_temp_s <= $index_s} {
						set index_temp_s [string first " " $msg_rem [expr {$index_s + 1}]]
						if {$index_temp_s >= 0 && $index_temp_s < $max_line} {
							set index_s $index_temp_s
						}
					}
					if {$index_s < 0} {
						set index_s [expr {[string length $msg_rem] - 1}]
					}


					set msg_cur [string range $msg_rem 0 $index_s]
					set msg_rem [string range $msg_rem [expr {$index_s + 1}] end]

					if {$lnum == 0} {
						log_output "${prefix}${log_tab}${msg_cur} \\"
					} else {
						log_output "${prefix}${log_tab}\t${msg_cur} \\"
					}
					set lnum [expr {$lnum + 1}]
				}

				log_output "${prefix}${log_tab}\t${msg_rem}"
			}
		}
	}

	proc log_section {name {boldness 1}} {
		variable section_line
		variable log_tab

		set separator [string repeat "#" $section_line]

		log_output ""
		log_output ""
		for {set i 0} {$i < $boldness} {incr i} {
			log_output "\t${log_tab}$separator"
		}

		set lrboldness [expr {$boldness * 2}]
		set lrseparator "[string repeat \# $lrboldness][string repeat \  [expr {$section_line - 2 * $lrboldness}]][string repeat \# $lrboldness]"
		log_output "\t${log_tab}$lrseparator"

		set title_first [expr {$section_line / 2 - [string length $name] / 2}]
		set title_last  [expr {$title_first + [string length $name] - 1}]
		log_output "\t${log_tab}[string replace $lrseparator $title_first $title_last $name]"

		log_output "\t${log_tab}$lrseparator"

		for {set i 0} {$i < $boldness} {incr i} {
			log_output "\t${log_tab}$separator"
		}
	}

	variable log_to_file   "false"
	variable log_to_stdout "true"
	variable log_fd -1

	proc set_log_file {filename {append_mode "true"}} {
		variable log_fd
		variable log_to_file

		if {$log_fd != -1} {
			close $log_fd
		}

		if {$append_mode} {
			set log_fd [open $filename "a"]
		} else {
			set log_fd [open $filename "w"]
		}

		set log_to_file "true"
	}

	proc close_log_file {} {
		variable log_fd

		close $log_fd
	}

	proc set_log_mode {{mode "both"}} {
		variable log_to_file
		variable log_to_stdout
		switch $mode {
			"both" {
				set log_to_file   "true"
				set log_to_stdout "true"
			}
			"file" {
				set log_to_file   "true"
				set log_to_stdout "false"
			}
			"stdout" {
				set log_to_file   "false"
				set log_to_stdout "true"
			}
		}
	}

	proc log_output {msg} {
		variable log_to_file
		variable log_to_stdout
		variable log_fd

		if {$log_to_file && ($log_fd != -1)} {
			puts $log_fd $msg
		}
		if {$log_to_stdout} {
			puts $msg
		}
	}

	proc log_indent {} {
		variable log_tab

		set log_tab "${log_tab}\t"
	}

	proc log_unindent {} {
		variable log_tab

		set l [string length $log_tab]

		if {$l > 0} {
			set log_tab [string range $log_tab 0 [expr {$l - 2}]]
		}
	}
}


namespace eval btrbackup {
	##########################
	## configuration        ##
	##########################
	namespace eval config {
		# temporary storage for config information
		namespace eval current {
			variable name ""
			variable name_valid "false"

			variable mountpoint ""
			variable mountpoint_valid "false"

			variable target_list {}
			variable target_list_valid "false"

			variable sync_rules {}
			variable sync_rules_valid "false"
		}

		variable config_error "false"
		# list of all config data
		variable config_list {}

		# commit current configuration
		proc commit {} {
			variable config_error
			variable config_list

			if {! $current::name_valid} {
				set config_error "true"
				::log::log_error "No valid config-name set."
			}
			if {! $current::mountpoint_valid} {
				set config_error "true"
				::log::log_error "No valid target mountpoint configured for $current::name."
			}
			if {! $current::target_list_valid} {
				set config_error "true"
				::log::log_error "No valid target subvolumes configured for $current::name."
			}
			if {! $current::sync_rules_valid} {
				set config_error "true"
				::log::log_error "No sync rules configured for $current::name."
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
			variable name ""
			variable name_valid "false"

			variable rules_list {}
			variable rules_valid "false"
		}

		variable config_error "false"
		variable config_list {}

		# commit current configuration
		proc commit {} {
			variable config_error
			variable config_list

			if {! $current::name_valid} {
				set config_error "true"
				::log::log_error "No valid expire-ruleset-name set."
			}

			if {! $current::rules_valid} {
				set config_error "true"
				::log::log_error "No expire rules configured for $current::name."
			}

			lappend config_list [list $current::name $current::rules_list]

			set current::name ""
			set current::name_valid "false"
			set current::rules_list {}
			set current::rules_valid "false"
		}
	}

	### expire rule configuration
	proc new_expire_ruleset {name} {
		if {$name == ""} {
			::log::log_error "Ruleset-name must be non-empty."
			set expireconfig::config_error "true"
			return
		}
		if {$expireconfig::current::name_valid} {
			::log::log_error "Expire ruleset $current::name not yet committed."
			set expireconfig::config_error "true"
			return
		}
		set expireconfig::current::name $name
		set expireconfig::current::name_valid "true"
	}

	proc add_expire_rule {rule parameter} {
		if {[llength [info procs "expire::rules::$rule"]] < 1} {
			::log::log_error "Expire rule $rule does not exist"
			set expireconfig::config_error "true"
			return
		}

		if {!([string is integer $parameter] || $parameter == "all")} {
			::log::log_error "Expire rule parameter must be \"all\" or a number"
			set expireconfig::config_error "true"
			return
		}

		lappend expireconfig::current::rules_list [list $rule $parameter]
		set expireconfig::current::rules_valid "true"
	}

	proc commit_expire_ruleset {} {
		expireconfig::commit
	}

	### backup target configuration
	proc new_config {name} {
		if {$name == ""} {
			::log::log_error "Config-name must be non-empty."
			set config::config_error "true"
			return
		}
		if {$config::current::name_valid} {
			::log::log_error "Config $current::name not yet committed."
			set config::config_error "true"
			return
		}
		set config::current::name $name
		set config::current::name_valid "true"
	}

	proc mountpoint {value} {
		if {![file exists $value]} {
			::log::log_error "Mountpoint $value does not exist."
			set config::config_error "true"
			return
		}
		set config::current::mountpoint $value
		set config::current::mountpoint_valid "true"
	}

	proc add_target_subvol {subvol snapshot_dir expire_ruleset} {
		if {$subvol == ""} {
			::log::log_error "Subvol-name must be non-empty."
			set config::config_error "true"
			return
		}
		if {[lsearch -index 0 $expireconfig::config_list $expire_ruleset] < 0} {
			::log::log_error "$expire_ruleset is no valid expire-ruleset"
			set config::config_error "true"
			return
		}

		lappend config::current::target_list $subvol $snapshot_dir $expire_ruleset
		set config::current::target_list_valid "true"
	}

	proc add_sync_rule {src_mountpoint src_subvol target_subvol target_subdir exclude_list} {
		if {$src_mountpoint == ""} {
			::log::log_error "Source-mointpoint must be non-empty."
			set config::config_error "true"
			return
		}
		if {$src_subvol == ""} {
			::log::log_error "Source-subvolume must be non-empty."
			set config::config_error "true"
			return
		}
		if {$target_subvol == ""} {
			::log::log_error "Target-subvolume must be non-empty."
			set config::config_error "true"
			return
		}

		if {[expr {[lsearch $config::current::target_list $target_subvol] % 3}] != 0} {
			::log::log_error "Target-subvolume $target_subvol is not configured in current target-list."
			set config::config_error "true"
			return
		}
		if {[expr {[lsearch $config::current::sync_rules $src_mountpoint] % 2}] != 0} {
			lappend config::current::sync_rules $src_mountpoint {}
		}

		set i_current [expr {[lsearch $config::current::sync_rules $src_mountpoint] + 1}]
		set new_synclist [linsert [lindex $config::current::sync_rules $i_current] end $src_subvol $target_subvol $target_subdir $exclude_list]
		set config::current::sync_rules [lreplace $config::current::sync_rules $i_current $i_current $new_synclist]

		set config::current::sync_rules_valid "true"
	}

	proc add_sync_rule_nobtr {src_directory target_subvol target_subdir exclude_list} {
		add_sync_rule "#NONE" $src_directory $target_subvol $target_subdir $exclude_list
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

				set startrange [expr {[llength $datelist] - $n}]

				return [lrange $datelist $startrange end]
			}

			proc firstofyear {n datelist} {
				if {[llength $datelist] < 1} {
					return {}
				}

				set startyear [expr {[lindex $datelist 0 0] - 1}]

				if {$n != "all"} {
					set startyear [expr {[clock format [clock seconds] -format "%Y"] - $n}]
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

				set startyear  [expr {[lindex $datelist 0 0]}]
				set startmonth 0

				if {$n != "all"} {
					set startyear  [expr {[clock format [clock seconds] -format "%Y"]}]
					set startmonth [expr {[clock format [clock seconds] -format "%N"] - $n}]

					while {$startmonth < 0} {
						set startyear  [expr {$startyear - 1}]
						set startmonth [expr {$startmonth + 12}]
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

				set target_date [expr {[clock seconds] - $n * 3600 * 24}]
				set startyear  [expr {[clock format $target_date -format "%Y"]}]
				set startmonth [expr {[clock format $target_date -format "%N"]}]
				set startday   [expr {[clock format $target_date -format "%e"]}]

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
				::log::log_debug "keeplist: $keeplist"

				set new_rmlist {}

				foreach i_rmitem $rmlist {
					if {[lsearch $keeplist $i_rmitem] < 0} {
						lappend new_rmlist $i_rmitem
					}
				}

				::log::log_debug "new rmlist: $new_rmlist"

				set rmlist $new_rmlist
			}

			return $rmlist
		}

		proc expire_snapshot_dir {nameprefix rulelist} {
			set date_snapshot_list {}
			set date_list {}

			# create lists
			set re "${nameprefix}\[0\]*(\[0-9\]+)-\[0\]*(\[0-9\]+)-\[0\]*(\[0-9\]+)_\[0\]*(\[0-9\]+)-\[0\]*(\[0-9\]+)"

			if {[catch {glob "${nameprefix}*"} snapshot_globs]} {
				return "true"
			}

			foreach i_snapshot $snapshot_globs {
				if {[regexp $re $i_snapshot full year month day hour minute]} {
					set date [list $year $month $day $hour $minute]
					lappend date_list $date
					lappend date_snapshot_list [list $date $i_snapshot]
				}
			}

			# expire list
			set expire_dates [get_expire_list $date_list $rulelist]

			# remove expired
			::log::log_indent
			foreach i_date $expire_dates {
				set ds_idx [lsearch -index 0 $date_snapshot_list $i_date]
				set i_snapshot [lindex $date_snapshot_list $ds_idx 1]

				::log::log_info "Deleting snapshot $i_snapshot"

				if {[catch {exec btrfs subvolume delete "${i_snapshot}"} data]} {
					::log::log_error "Failed to delete snapshot $i_snapshot"
					::log::log_info $data
					::log::log_unindent
					return "false"
				}
			}

			exec sleep 10

			::log::log_unindent
			return "true"
		}
	}



	##########################
	## Backup Execution     ##
	##########################
	namespace eval run {
		variable src_snapshot_prefix "bckp-snp-"
		variable rsyn_opts [list "-axsvXA" "--delete"]

		proc create_src_snapshots_from_list {fs_mountpoint snapshot_list snapshot_prefix} {
			if {[llength $snapshot_list] <= 0} {
				return "true"
			}
			# non-snapshot sources
			if {$fs_mountpoint == "#NONE"} {
				return "true"
			}

			set current_subvol [lindex $snapshot_list 0]
			set remaining_list [lreplace $snapshot_list 0 0]

			cd $fs_mountpoint

			if {[catch {exec btrfs subvolume snapshot $current_subvol "${snapshot_prefix}${current_subvol}"} data]} {
				::log::log_error "Failed to create snapshot of $current_subvol in ${snapshot_prefix}${current_subvol}"
				::log::log_info $data
				return "false"
			} else {
				::log::log_info "Created snapshot of $current_subvol in ${snapshot_prefix}${current_subvol}"
			}

			if {[create_src_snapshots_from_list $fs_mountpoint $remaining_list $snapshot_prefix]} {
				return "true"
			} else {
				cd $fs_mountpoint
				if {[catch {exec btrfs subvolume delete "${snapshot_prefix}${current_subvol}"} data]} {
					::log::log_error "Failed to delete snapshot ${snapshot_prefix}${current_subvol} of $current_subvol"
					::log::log_info $data
				} else {
					::log::log_info "Deleted snapshot ${snapshot_prefix}${current_subvol} of $current_subvol"
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

			# non-snapshot sources
			if {$current_mountpoint != "#NONE"} {
				if {[catch {exec mount $current_mountpoint} data]} {
					::log::log_error "Failed to mount $current_mountpoint"
					::log::log_info $data
					return "false"
				} else {
					::log::log_info "Mounted $current_mountpoint"
				}
			}

			set result "true"

			::log::log_indent
			if {[create_src_snapshots_from_list $current_mountpoint $snapshot_list $snapshot_prefix]} {
				::log::log_unindent
				set result [prepare_src_snapshots [lreplace $backup_src_list 0 1] $snapshot_prefix]

				if {! $result} {
					cleanup_src_snapshots_from_list $current_mountpoint $snapshot_list $snapshot_prefix
				}
			} else {
				::log::log_unindent
				set result "false"
			}

			if {! $result} {
				cd /
				exec sleep 10
				# non-snapshot sources
				if {$current_mountpoint != "#NONE"} {
					if {[catch {exec umount $current_mountpoint} data]} {
						::log::log_error "Failed to umount $current_mountpoint"
						::log::log_info $data
					} else {
						::log::log_info "Umounted $current_mountpoint"
					}
				}
			}

			return $result
		}

		proc cleanup_src_snapshots_from_list {fs_mountpoint snapshot_list snapshot_prefix} {
			if {[llength $snapshot_list] <= 0} {
				return "true"
			}
			# non-snapshot sources
			if {$fs_mountpoint == "#NONE"} {
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
				::log::log_error "Failed to delete snapshot ${snapshot_prefix}${current_subvol} of $current_subvol"
				::log::log_info $data
				return "false"
			} else {
				::log::log_info "Deleted snapshot ${snapshot_prefix}${current_subvol} of $current_subvol"
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
			# non-snapshot sources
			if {$current_mountpoint != "#NONE"} {
				if {[catch {exec umount $current_mountpoint} data]} {
					::log::log_error "Failed to umount $current_mountpoint"
					::log::log_info $data
					set result "false"
				} else {
					::log::log_info "Umounted $current_mountpoint"
				}
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
					if {$i_src_mnt == "#NONE"} {
						set cur_srcdir "${j_src_vol}"
					} else {
						set cur_srcdir "${i_src_mnt}/${snapshot_prefix}${j_src_vol}"
					}
					set cur_tardir "${target_mountpoint}/${j_target_vol}${j_target_subdir}"

					set cur_cmd [list "nice" "-n" "19" "rsync"]

					foreach opt $rsyn_opts {
						lappend cur_cmd $opt
					}

					foreach excl $j_excludes {
						lappend cur_cmd "--exclude"
						lappend cur_cmd "${excl}/**"
					}

					if {$cur_srcdir == "/"} {
						lappend cur_cmd "/"
					} else {
						lappend cur_cmd "${cur_srcdir}/"
					}
					lappend cur_cmd "${cur_tardir}"

					::log::log_info "Syncing volume $j_src_vol"
					if {[catch {eval exec $cur_cmd} data]} {
						::log::set_log_mode "file"
						::log::log_indent
						foreach line [split $data "\n"] {
							::log::log_info $line
						}
						::log::log_unindent
						::log::set_log_mode "both"

						::log::log_error "Failed to sync $cur_srcdir to $cur_tardir"
						set result "false"
					} else {
						::log::set_log_mode "file"
						::log::log_indent
						foreach line [split $data "\n"] {
							::log::log_info $line
						}
						::log::log_unindent
						::log::set_log_mode "both"

						::log::log_info "Synced $cur_srcdir to $cur_tardir"
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
					::log::log_error "Could not create snapshot of $i_vol"
					::log::log_info $data
					set result "false"
				} else {
					::log::log_info "Created snapshot of $i_vol"
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
			::log::log_info "Deleting expired snapshots of subvolume $subvolume"
			cd $snapshot_dir

			set ruleset_index [lsearch -index 0 [set "[namespace parent]::expireconfig::config_list"] $expire_ruleset]
			if {$ruleset_index < 0} {
				::log::log_error "Could not find expire-ruleset $expire_ruleset"
				return "false"
			}

			set ruleset [lindex [set "[namespace parent]::expireconfig::config_list"] $ruleset_index 1]

			return [[namespace parent]::expire::expire_snapshot_dir "$subvolume-" $ruleset]
		}

		proc expire_run {target_mountpoint target_list} {

			foreach {i_vol i_dir i_exprule} $target_list {
				if {! [expire_target $i_vol "${target_mountpoint}/$i_dir" $i_exprule]} {
					::log::log_error "Failed to delete expired snapshotfs of $i_vol"
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
				::log::log_error "Failed to mount $target_mountpoint"
				::log::log_info $data
				return "false"
			} else {
				::log::log_info "Mounted target $target_mountpoint"
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
				::log::log_error "Failed to umount $target_mountpoint"
				::log::log_info $data
				return "false"
			} else {
				::log::log_info "Umounted target $target_mountpoint"
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
		::log::set_log_mode "stdout"

		if {$::argc != 1} {
			::log::log_error "Need exactly 1 argument: name of backup configuration to run"
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
			::log::log_error "Invalid configuration"
			return "false"
		}

		if {[lsearch -index 0 $config::config_list $config_to_use] < 0} {
			::log::log_error "Config $config_to_use not found."
			puts ""
			help
			return "false"
		}

		::log::set_log_mode "both"

		::log::log_section "Running Backup $config_to_use - [clock format [clock seconds] -format "%Y-%m-%d %H:%M"]" 2

		set config_data [lindex $config::config_list [lsearch -index 0 $config::config_list $config_to_use]]

		set target_mountpoint [lindex $config_data 1]
		set target_list       [lindex $config_data 2]
		set src_list          [lindex $config_data 3]
		set result [run::stage0 $target_mountpoint $target_list $src_list]

		if {$result} {
			::log::log_info "Backup ran successfully"
		} else {
			::log::log_error "Errors occured"
		}
	}
}

## open log-file
log::set_log_file "/var/log/btrbackup.log"
log::set_log_level "INFO"

## read in configuration data and execute backup
source "/etc/btrbackupconfig.tcl"

btrbackup::run_backup

log::close_log_file
