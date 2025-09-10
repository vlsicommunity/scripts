#-----------------------------------
# File    : star.tcl 
# Part of STAR - STA-Reporting
# Author  : Harish Kumar R 
# harishkumar.rajendrababu@nxp.com
#------------------------------------

package require Tcl 8.5

# Cleanup the config variables before initializing
foreach var [info vars ::star::*] {
  if {[info exist $var]} {unset $var} 
}

namespace eval star {

  variable v_hier_map 
  variable v_mode_grp
  variable v_tool_vendor
  variable v_tool_name
  variable v_tool_mode
  variable v_flow_name

  variable v_supported_vendor {}
  variable v_supported_tool {}
  variable v_supported_tool_mode {}
  variable v_supported_flow {}

  # Supported tools
  lappend ::star::v_supported_vendor snps
  lappend ::star::v_supported_tool pt_shell
  lappend ::star::v_supported_tool_mode primetime
  lappend ::star::v_supported_tool_mode primetime_master
  lappend ::star::v_supported_tool_mode primetime_slave
  lappend ::star::v_supported_flow nxcode
  lappend ::star::v_supported_flow lynx
}

set ::star::debug 1

proc ::star::printBanner {} {
  
  puts ""
  puts ""
  puts "Calling..."
  puts ""
  puts "    ____    ________      _        ______  "
  puts "   / ___`  /___  ___\\    / \\      /  __  \\ "
  puts "   \\___ \\      | |      / _ \\     | |__|_) "
  puts "    ___) )     | |     / /_\\ \\    |  __ \\  "
  puts "   (____/      |_|    /_/   \\_\\   |_|  \\_\\ "
  puts "                                          "
  puts "                        STA-Reporting System  "
  puts ""
  puts "  Developer : harishkumar.rajendrababu@nxp.com"
  puts "  version   : STAR_release_003                "                             
  puts ""
  puts ""
  after 2000



}


proc ::star::attrDefined {obj attr} {

  set check \
    [filter_collection $obj defined($attr)]

  if {[sizeof_col $check]} {

    set ovalue [get_object_name \
	    [get_attribute $obj $attr]]

    return $ovalue

  } else {

    return "undef"

  }
  
}

proc ::star::parseArgs {} {

  set args_count 0
  set args_ok    1

  if { $::star::debug } { 
    puts "STAR> Debug: Number of args : $::argc" 
  }

  while { $args_ok && ($args_count < $::argc) } {

    if {$::star::debug} {
      puts -nonewline "STAR> Deug: Checking for arg "
      puts "[lindex $::argv $args_count]" 
    }

    switch -glob -- [lindex $::argv $args_count] {

      -config  { 
        incr args_count; 
        if { $args_count < $::argc } { 
          set ::star::args(config) [lindex $::argv $args_count]
        }
      }

      -help { short_help }

      --help { long_help }

      default { set args_ok 0 }

    }
    incr args_count
  }

}


proc ::star::readConfig {} {

  if {0} {
    set fp [open \
      "$::star::resourceDir/star_config.yaml" r]  
    set ::star::config \
      [::yaml::yaml2dict [read $fp]]
    close $fp
  }

  # Call py to read config
  exec /pkg/OSS-python-/3.9.13/x86_64-linux/bin/python3 \
	 $::star::resourceDir/star.py \
	 "rc" \
	 [pwd]

  
  # Source config settings into the shell
  source [pwd]/.sc


}


# Check resorces
proc ::star::checkResources {} {

  set resources {}
  lappend resources cmdline.tcl
  lappend resources huddle_types.tcl
  lappend resources huddle.tcl
  lappend resources yaml.tcl
  #lappend resources star.py

  set ::star::resourceDir [file normalize \
                 [file dirname [info script]]]

  set resourceCheck 1
  foreach fileItem $resources {
    if {![file exist $::star::resourceDir/$fileItem]} {
      puts -nonewline "STAR> Error: Expected resource file "
      puts "$fileItem not found under $::star::resourceDir"
      set $resourceCheck 0
    } else {
      puts "STAR> Loading resource file $fileItem..."
      after 2000
      redirect -var null {
	source $::star::resourceDir/$fileItem
      }
    }
  }

  if {![file exist "$::star::resourceDir/star.py"]} {
    puts -nonewline "STAR> Error: Expected resource file "
    puts "star.py not found under $::star::resourceDir/"
    set $resourceCheck 0
  }

  if {![file exist "$::star::resourceDir/star_config.yaml"]} {
    puts -nonewline "STAR> Error: Expected resource file "
    puts "star_config.yaml not found under $::star::resourceDir"
    set $resourceCheck 0
  }
  return $resourceCheck
}

#------------------------------------------------
# Check the envireonment in which STAR is called
#------------------------------------------------

proc ::star::envCheck {} {

  global synopsys_program_name
  global pt_shell_mode
  global LYNX
  global nxvars

  if {[info exist synopsys_program_name]} {
    set ::star::v_tool_vendor "snps"
  } else {
    set ::star::v_tool_vendor "uK"
  }
  
  if {$::star::v_tool_vendor eq "snps"} {
    set ::star::v_tool_name $synopsys_program_name
  }
 
  if {$::star::v_tool_name eq "pt_shell"} {
    set ::star::v_tool_mode $pt_shell_mode
  } else {set ::star::v_tool_mode "uK"}
  
  if {$::star::v_tool_mode eq "primetime_master"} {
    redirect -var null {
      get_distributed_variable LYNX -merge_type unique
      get_distributed_variable nxvars -merge_type unique
    }
  }
  
  if {[info exist LYNX]} {
    set ::star::v_flow_name "lynx"
  } elseif {[info exists nxvars]} {
    set ::star::v_flow_name "nxcode"
  } else {set ::star::v_flow_name "uK"}

  puts "STAR> Identified env settings,"
  puts "\tTool vendor : $::star::v_tool_vendor"
  puts "\tTool name   : $::star::v_tool_name"
  puts "\tTool mode   : $::star::v_tool_mode"
  puts "\tFlow name   : $::star::v_flow_name"

}

#------------------------------------------------
# Read user config
#------------------------------------------------
# Configuration for reporting based on hierarchy 
#set ::star::v_hier_map(vpu) imx95_vpumix_wrapper/
#append ::star::v_hier_map(ctx) imx95_cortexamix_wrapper/ 
#append ::star::v_hier_map(ddr) imx95_ddrmix_wrapper/ 
#append ::star::v_hier_map(wkp) imx95_wakeupmix_wrapper/ 
#append ::star::v_hier_map(dsp) imx95_displaymix_wrapper/ 
#append ::star::v_hier_map(gpu) imx95_gpumix_wrapper/ 
#append ::star::v_hier_map(npu) imx95_npumix_wrapper/

# Configuration for reporting based on modes
#set ::star::v_mode_grp(FUNC) {
#	               FUNC_UD
#		       FUNC_NM
#		       FUNC_OD}
#set ::star::v_mode_grp(ATSPEED) {
#                       ATPG_ATSPEED_UD
#	               ATPG_ATSPEED_NM
#	               ATPG_ATSPEED_OD
#	               ATPG_ATSPEED_UD_SOC_ATPG_ATSPEED_SOD_ARM
#	               ATPG_ATSPEED_NM_SOC_ATPG_ATSPEED_SOD_ARM
#	               ATPG_ATSPEED_OD_SOC_ATPG_ATSPEED_SOD_ARM}
#set ::star::v_mode_grp(SHIFT) {
#                       ATPG_SHIFT_UD
#	               ATPG_SHIFT_NM
#	               ATPG_SHIFT_OD
#	               ATPG_SHIFT_OD_SOC_ATPG_SHIFT_SOD_ARM
#	               ATPG_SHIFT_UD_SOC_ATPG_SHIFT_SOD_ARM}
#set ::star::v_mode_grp(STUCKAT) {
#                       ATPG_STUCKAT_UD
#	               ATPG_STUCKAT_NM
#	               ATPG_STUCKAT_OD}

# Unix out directory in which eng_view will be written
# This input is optional. Default is to write to 
# $cwd/star_yYYmMMdDD_<incrNum>
set ::star::v_output_dir ""

# Config to indicate slack limit for reporting
set ::star::v_rpt_setup_slack_lt inf
set ::star::v_rpt_hold_slack_lt inf

# Config to limit the max paths 
set ::star::v_rpt_setup_max_paths 10000
set ::star::v_rpt_hold_max_paths 10000

#------------------------------------------------
# Proc to validate the user config
#------------------------------------------------
proc ::star::validateInputs {} {

  global mode
  global rc_corner
  global rc_corner_notemp

  set ::star::valInputsFlag 1
  if {[lsearch -exact \
    $::star::v_supported_flow $::star::v_flow_name] < 0} {
    puts -nonewline "STAR> Error STAR does not support"
    puts " flow -->$::star::v_flow_name<--"
    set ::star::valInputsFlag 0
  }

  if {[lsearch -exact \
    $::star::v_supported_vendor $::star::v_tool_vendor] < 0} {
    puts -nonewline "STAR> Error STAR does not support"
    puts " tool vendor -->$::star::v_tool_vendor<--"
    set ::star::valInputsFlag 0
  }

  if {[lsearch -exact \
    $::star::v_supported_tool $::star::v_tool_name] < 0} {
    puts -nonewline "STAR> Error STAR does not support"
    puts " tool -->$::star::v_tool_name<--"
    set ::star::valInputsFlag 0
  }


  dict for {key value} \
    [dict get $::star::config star_hier_map] {
    set ::star::v_hier_map($key) $value
  }

  dict for {key value} \
    [dict get $::star::config star_mode_grp] {
    set ::star::v_mode_grp($key) $value
  }

  if {![dict exist $::star::config \
	 timing_query_settings pba_mode]} {

    puts -nonewline "STAR> Warning: Required config "
    puts -nonewline "variable -->pba_mode<--"
    puts " not found under timing_query_settings." 
    set ::star::timing_pba_mode "none"

  } else {
    set ::star::timing_pba_mode \
      [dict get $::star::config \
          timing_query_settings pba_mode]
  }
     
  if {![dict exist $::star::config \
	 timing_query_settings setup_nworst]} {

    puts -nonewline "STAR> Warning: Required config "
    puts -nonewline "variable -->setup_nworst<--"
    puts -nonewline " not found under timing_query_settings." 
    puts "Defaulting to SETUP_NWORST of 1."
    set ::star::timing_setup_nworst 1

  } else {

    set ::star::timing_setup_nworst \
      [dict get $::star::config \
          timing_query_settings setup_nworst]

  }

  if {![dict exist $::star::config \
	 timing_query_settings hold_nworst]} {

    puts -nonewline "STAR> Warning: Required config "
    puts -nonewline "variable -->hold_nworst<--"
    puts -nonewline " not found under timing_query_settings." 
    puts "Defaulting to HOLD_NWORST of 1."
    set ::star::timing_hold_nworst 1

  } else {

    set ::star::timing_hold_nworst \
      [dict get $::star::config \
          timing_query_settings hold_nworst]

  }

  if {![dict exist $::star::config \
	 timing_query_settings setup_slack_lt]} {

    puts -nonewline "STAR> Warning: Required config "
    puts -nonewline "variable -->setup_slack_lt<--"
    puts " not found under timing_query_settings." 
    set ::star::v_rpt_setup_slack_lt 0

  } else {
    set ::star::v_rpt_setup_slack_lt \
      [dict get $::star::config \
          timing_query_settings setup_slack_lt]
  }

  if {![dict exist $::star::config \
	 timing_query_settings hold_slack_lt]} {

    puts -nonewline "STAR> Warning: Required config "
    puts -nonewline "variable -->hold_slack_lt<--"
    puts " not found under timing_query_settings." 
    set ::star::v_rpt_hold_slack_lt 0
  } else {
    set ::star::v_rpt_hold_slack_lt \
      [dict get $::star::config \
          timing_query_settings hold_slack_lt]
  }

  if {![dict exist $::star::config \
	 timing_query_settings setup_max_paths]} {

    puts -nonewline "STAR> Warning: Required config "
    puts -nonewline "variable -->setup_max_paths<--"
    puts " not found under timing_query_settings." 
    set ::star::v_rpt_setup_max_paths 2000000
  } else {
    set ::star::v_rpt_setup_max_paths \
      [dict get $::star::config \
          timing_query_settings setup_max_paths]
  }

  if {![dict exist $::star::config \
	 timing_query_settings hold_max_paths]} {

    puts -nonewline "STAR> Warning: Required config "
    puts -nonewline "variable -->hold_max_paths<--"
    puts " not found under timing_query_settings." 
    set ::star::v_rpt_hold_max_paths 2000000
  } else {
    set ::star::v_rpt_hold_max_paths \
      [dict get $::star::config \
          timing_query_settings hold_max_paths]
  }

  if {![dict exist $::star::config \
	 timing_query_settings verbose_rpt_max_paths]} {

    puts -nonewline "STAR> Warning: Required config "
    puts -nonewline "variable -->verbose_rpt_max_paths<--"
    puts " not found under timing_query_settings." 
    set ::star::verbose_rpt_max_paths 2000000

  } else {

    set ::star::verbose_rpt_max_paths \
      [dict get $::star::config \
          timing_query_settings verbose_rpt_max_paths]
  }

  if {![dict exist $::star::config \
	 timing_query_settings path_types]} {

    puts -nonewline "STAR> Warning: Required config "
    puts -nonewline "variable -->path_types<--"
    puts -nonewline " not found under timing_query_settings."
    puts " All path_types will be reported." 
    set ::star::v_rpt_path_types {
                              "reg_to_reg"
                              "reg_to_out"
                              "in_to_reg"
                              "in_to_out"}

  } else {
    set ::star::v_rpt_path_types \
      [dict get $::star::config \
          timing_query_settings path_types]
  }

  if {![dict exist $::star::config \
	 timing_query_settings rpt_types]} {

    puts -nonewline "STAR> Warning: Required config "
    puts -nonewline "variable -->rpt_types<--"
    puts -nonewline " not found under timing_query_settings."
    puts -nonewline " Both summary & verbose will be reported 
    set ::star::rpt_types {
                         "summary"
                         "verbose"}

  } else {
    set ::star::rpt_types \
      [dict get $::star::config \
          timing_query_settings rpt_types]
  }

  # Checks to be performed when the shell is a dmsa
  if {$::star::v_tool_mode eq "primetime_master"} {

    # Check presence of the mode grp config input
    if {![info exist ::star::v_mode_grp]} {
      puts -nonewline "STAR> Error: Required config "
      puts -nonewline "variable -->::star::v_mode_grp<--"
      puts " not found. Please define it and rerun" 
      set ::star::valInputsFlag 0
    } else {
      # Take only the valid mode groupings
      foreach var_i [array names ::star::v_mode_grp] {
	foreach var_mode $::star::v_mode_grp($var_i) {
	  redirect -var temp {
            catch {current_scenario ${var_mode}.*}
	  }
          if {![regexp "Error" $temp]} {
	    lappend ::star::modeGrpClean($var_i) $var_mode
	  } else {
            puts -nonewline "STAR> Info: Mode -->$var_mode<--"
            puts -nonewline " has no corresponding scenarios in "
            puts "this dmsa. Correct it if this is unintended" 
          }
	  current_scenario -all
	}
      }
    }

    if {![info exist ::star::modeGrpClean]} {
      puts -nonewline "STAR> Error: None of the mode "
      puts -nonewline "defined in -->::star::v_mode_grp<--"
      puts "has any valid scenario. " 
      set ::star::valInputsFlag 0
    } else {
      # Get the setup and hold scenarios for the valid modes
      foreach starModeGrp [array names ::star::modeGrpClean] {
        foreach starMode $::star::modeGrpClean($starModeGrp) {
	  if {$::star::v_flow_name eq "lynx"} {
	    redirect -var setupSceneCheck {
              catch {current_scenario ${starMode}*T}
	    }
            if {![regexp "Error" $setupSceneCheck]} {
              set ::star::modeGrpSceneMap($starModeGrp,$starMode,max) \
	        [current_scenario ${starMode}*T]
	    }
	    redirect -var holdSceneCheck {
              catch {current_scenario ${starMode}*t}
	    }
            if {![regexp "Error" $holdSceneCheck]} {
              set ::star::modeGrpSceneMap($starModeGrp,$starMode,min) \
	        [current_scenario ${starMode}.*t]
            }
	  }
	  if {$::star::v_flow_name eq "nxcode"} {
	    redirect -var setupSceneCheck {
              catch {current_scenario ${starMode}*_T_*}
	    }
            if {![regexp "Error" $setupSceneCheck]} {
              set ::star::modeGrpSceneMap($starModeGrp,$starMode,max) \
	        [current_scenario ${starMode}*_T_*]
	    } 

	    redirect -var holdSceneCheckM40 {
              catch {current_scenario ${starMode}*t_m40}
	    }
            if {![regexp "Error" $holdSceneCheckM40]} {
              append_to_col \
		::star::modeGrpSceneMap($starModeGrp,$starMode,min) \
	        [current_scenario ${starMode}*t_m40]
	    }

	    redirect -var holdSceneCheck125 {
              catch {current_scenario ${starMode}*t_125}
	    }
            if {![regexp "Error" $holdSceneCheck125]} {
              append_to_col \
		::star::modeGrpSceneMap($starModeGrp,$starMode,min) \
	        [current_scenario ${starMode}*t_125]
            }
 
	    # For MBIST TCU/HVST
	    redirect -var holdSceneCheck025 {
              catch {current_scenario ${starMode}*t_025}
	    }
            if {![regexp "Error" $holdSceneCheck025]} {
              append_to_col \
		::star::modeGrpSceneMap($starModeGrp,$starMode,min) \
	        [current_scenario ${starMode}*t_025]
            }

	    # For MBIST TCU/HVST
	    redirect -var holdSceneCheck150 {
              catch {current_scenario ${starMode}*t_150}
	    }
            if {![regexp "Error" $holdSceneCheck150]} {
              append_to_col \
		::star::modeGrpSceneMap($starModeGrp,$starMode,min) \
	        [current_scenario ${starMode}*t_150]
            }

          }
	}
      }
    }

  } else {

    if {[info exists mode]} {
      foreach var_i [array names ::star::v_mode_grp] {
	foreach var_mode $::star::v_mode_grp($var_i) {
          if {$mode eq $var_mode} {
            lappend ::star::modeGrpClean($var_i) $var_mode
	  }
	}
      }

      if {![info exist ::star::modeGrpClean]} {
        puts -nonewline "STAR> Error: None of the mode "
        puts -nonewline "defined in -->::star::v_mode_grp<--"
        puts "has any valid scenario. " 
        set ::star::valInputsFlag 0
      } else {
        if {$::star::v_flow_name eq "nxcode"} {
          foreach starModeGrp [array names ::star::modeGrpClean] {
            foreach starMode $::star::modeGrpClean($starModeGrp) {
	      if {[info exists rc_corner_notemp]} {
	        if {[regexp {.*T} $::rc_corner_notemp]} {
  set ::star::modeGrpSceneMap($starModeGrp,$starMode,max) \
		    "valid"
	        } else {
  set ::star::modeGrpSceneMap($starModeGrp,$starMode,min) \
		    "valid"
	        }
	      }
	    }
	  }
	} 

        if {$::star::v_flow_name eq "lynx"} {
          foreach starModeGrp [array names ::star::modeGrpClean] {
            foreach starMode $::star::modeGrpClean($starModeGrp) {
	      if {[info exists rc_corner]} {
	        if {[regexp {.*T} $rc_corner]} {
  set ::star::modeGrpSceneMap($starModeGrp,$starMode,max) \
		    "valid"
	        } else {
  set ::star::modeGrpSceneMap($starModeGrp,$starMode,min) \
		    "valid"
	        }
	      }
	    }
	  }
	}
      }	
    } else {
      puts -nonewline "STAR> Error: Required variable -->mode<--"
      puts "not defined. Please define and rerun."
      set ::star::valInputsFlag 0
    }
  } 


  if {[lsearch -exact \
    $::star::v_supported_tool_mode $::star::v_tool_mode] < 0} {
    puts -nonewline "STAR> Error STAR does not support"
    puts " tool mode -->$::star::v_tool_mode<--"
    set ::star::valInputsFlag 0
  }


  if {[info exist ::star::v_hier_map]} {
    foreach var_i {"top" "input" "output" "hm"} {
      if {[lsearch -nocase -exact $var_i \
              [array names ::star::v_hier_map]] >=0} {
        puts -nonewline "STAR> Error : Reserved word "
        puts "-->$var_i<-- used as index in ::star::v_hier_map<--"
        set ::star::valInputsFlag 0
      }
    }

    foreach hierShort [array names ::star::v_hier_map] {
      set hierTempArray($hierShort) \
        [string trim $::star::v_hier_map($hierShort) "/"]
    }

    set key_value \
      [lmap {key val} [array get hierTempArray] {list $key $val}]
    set ::star::hierMapSorted \
      [lsort -index 1 -increasing $key_value]

  } else {
    puts -nonewline "STAR> Error : Expected config variable "
    puts "-->::star::v_hier_map<-- not defined in the config file"
    set ::star::valInputsFlag 0
  }

  #TODO: Check the validity of the hier map values
  # exit if something not found

  if {![info exist ::star::v_rpt_setup_slack_lt]} {
    puts -nonewline "STAR> Error : Expected config variable "
    puts "-->::star::v_rpt_setup_slack_lt<-- not defined in the config file"
    set ::star::valInputsFlag 0
  }
    
  if {![info exist ::star::v_rpt_hold_slack_lt]} {
    puts -nonewline "STAR> Error : Expected config variable "
    puts "-->::star::v_rpt_hold_slack_lt<-- not defined in the config file"
    set ::star::valInputsFlag 0
  }

  if {![info exist ::star::v_rpt_setup_max_paths]} {
    puts -nonewline "STAR> Info : Expected config variable "
    puts -nonewline "-->::star::v_rpt_setup_max_paths<-- not"
    puts " defined in the config file. Taking default 2000000"
    set ::star::v_rpt_setup_max_paths 2000000
  }
    
  if {![info exist ::star::v_rpt_hold_max_paths]} {
    puts -nonewline "STAR> Info : Expected config variable "
    puts -nonewline "-->::star::v_rpt_hold_max_paths<-- not"
    puts " defined in the config file. Taking default 2000000"
    set ::star::v_rpt_hold_max_paths 2000000
  }

  #if {[info exist ::star::v_output_dir]} {
  #  if {$::star::v_output_dir ne ""} {
  #    set ::star::unixOutDir "[pwd]/$::star::v_output_dir"
  #  } else {
  #    set ::star::unixOutDir \
  #"[pwd]/star_[clock format [clock seconds] -format {y%ym%md%d}]"
  #  }
  #} else {
  #  puts -nonewline "STAR> Warning : Required config variable "
  #  puts -nonewline "-->::star::v_output_dir<-- not defined. "
  #  puts "Outputs will be written here,"
  #  puts "[pwd]/star_[clock format [clock seconds] -format {y%ym%md%d}]"
  #  set ::star::unixOutDir \
  #"[pwd]/star_[clock format [clock seconds] -format {y%ym%md%d}]"
  #}


  if {[file exists $::star::unixOutDir]} {
    puts -nonewline "STAR> Info : Cleaning up already "
    puts "existing output directory..."
    puts " -->$::star::unixOutDir<--"
    catch {
      file delete -force $::star::unixOutDir/*
      sh rm -rf $::star::unixOutDir/*
    }
  }
          
  if {[catch \
        {file mkdir $::star::unixOutDir}]} {
    puts -nonewline "STAR> Error : Unable to create output "
    puts -nonewline "directory -->$::star::unixOutDir<--. Please "
    puts "check for write permissions current working dir."
    set ::star::valInputsFlag 0
  }

  return $::star::valInputsFlag
}

#------------------------------------------------
# Proc to exract info from NXvars
#------------------------------------------------
proc ::star::extractNxVars {} {

  set ::star::varExtractNxVars 1
  if {[info exist ::nxvars(design_stage)]} {
    set ::star::design_stage $::nxvars(design_stage)
  } else {
    puts -nonewline "STAR> Error: expected variable"
    puts " not found -->nxvars(design_stage)<--"
    set ::star::varExtractNxVars 0$::star::v_flow_name
  }

  return $::star::varExtractNxVars

}

#------------------------------------------------
# Proc to exract info from LYNX env
#------------------------------------------------
proc ::star::extractLynxVars {} {

  set ::star::varExtractLynxVars 1
  if {$::star::v_tool_mode eq "primetime_master"} {
    current_scenario -all
    global TEV
    redirect -var temp {
      get_distributed_variable TEV -merge_type unique
    }
    if {[regexp {Error} $temp]} {
      set ::star::varExtractLynxVars 0
      puts -nonewline "STAR> Error: Something went wrong"
      puts " while querying for TEV array..."
      puts $temp
    }
  }
  if {[info exist ::TEV(design_stage)]} {
    set ::star::design_stage $::TEV(design_stage)
  } else {
    puts -nonewline "STAR> Error: expected variable"
    puts " not found -->TEV(design_stage)<--"
    set ::star::varExtractLynxVars 0
  }

  return $::star::varExtractLynxVars

}
#------------------------------------------------
# exit proc
#------------------------------------------------
proc ::star::exit_star {} { 
  puts "#----------------------------------"
  puts "STAR> Abnormal exit                    "
  puts "#----------------------------------"
  return -code 0
}

proc ::star::indent {indentLvl} {
  return [string repeat " " $indentLvl]
}


proc ::star::writeTxtIndex {} {

  # Write a index file for each of the mode + delay combination
  # This is required as to proide easy debug mechanism for users
  # in unix

  foreach modeGrp [array names ::star::modeGrpClean] {

    #puts "debug: modeGrp is  are $modeGrp"
    foreach delay {"max" "min"} {
      #puts "debug: delay is  $delay"

      set arrayKeys \
        [array names ::star::modeGrpSceneMap \
          -regexp "$modeGrp,.+,$delay"]

      set modes {}
      foreach key $arrayKeys {
        lappend modes [lindex [split $key ","] 1]
      }

      if {[llength $arrayKeys]} {

	#puts "debug: modes are $modes"
   
	foreach mode $modes {

          puts "STAR> Writing index file for "
          puts "STAR>\t $mode"
          puts "STAR>\t $delay"

          set fp [open \
            "$::star::engineerViewDir/${mode}_$delay.txt" w] 


          puts $fp "#----------------------------------------"
	  puts $fp "#         Overview Table                 "
          puts $fp "#----------------------------------------"

	  puts $fp "[format "%10s %10s %15s   %-40s" \
		           "FEP" "WNS" "TNS" "Category"]"

          dict for {mainCat value} \
	    [dict get $::star::catTreeTiming $modeGrp $delay] {
            
	    #puts "debugX: $value"
            dict for {hierCat value} $value {

	      #puts "debugY : modeStats : $modeStats"

	      #puts "debugY: $value"

              if {$hierCat eq "mode_stats"} {

                set wns [dict get $value $mode "wns"]
                set tns [dict get $value $mode "tns"]
                set fep [dict get $value $mode "fep"]

	        puts $fp \
		  "[format "%10d %10.2f %15.2f   %-40s" \
		          $fep $wns $tns $mainCat]"

              }		      
	    }
          }

	  puts $fp ""

	  set printOnce 1
          dict for {mainCat value} \
	    [dict get $::star::catTreeTiming $modeGrp $delay] {
            
            dict for {hierCat value} $value {

              if {($hierCat ne "mode_stats") \
	             && ($hierCat ne "none")} {
         
	        if {$printOnce} { 
	          puts $fp "#----------------------------------------"
	          puts $fp "#        $mainCat Hierarchy Table        "
                  puts $fp "#----------------------------------------"
	          puts $fp ""
		  puts $fp "[format "%10s %10s %15s  %-40s" \
		           "FEP" "WNS" "TNS" "Category"]"
		  set printOnce 0
		}

                set wns [dict get $value "mode_stats" $mode "wns"]
                set tns [dict get $value "mode_stats" $mode "tns"]
                set fep [dict get $value "mode_stats" $mode "fep"]

	        puts $fp \
		  "[format "%10d %10.2f %15.2f   %-40s" \
		          $fep $wns $tns $hierCat]"

              }		      
	    }
          }

          dict for {mainCat value} \
	    [dict get $::star::catTreeTiming $modeGrp $delay] {
            
	    puts $fp ""
	    set printOnce 1
            dict for {hierCat value} $value {

              if {$hierCat ne "mode_stats"} {
         
	        if {$printOnce} { 
	          puts $fp "#----------------------------------------"
	          puts $fp "#        $mainCat Hierarchy+ClockGrp Table        "
                  puts $fp "#----------------------------------------"
	          puts $fp ""
		  puts $fp "[format "%10s %10s %15s   %-20s  %-20s  %-30s  %-40s" \
		    "FEP" "WNS" "TNS" "HierCat" "rptLnk" "ClkGrp" "ToClock:FromClock"]"
		  set printOnce 0
		}

		dict for {clkPair value} $value {
              
		  if {$clkPair ne "mode_stats"} {

		    dict for {clkGrp value} $value {

                      set wns [dict get $value "mode_stats" $mode "wns"]
                      set tns [dict get $value "mode_stats" $mode "tns"]
                      set fep [dict get $value "mode_stats" $mode "fep"]

                      if {[lsearch -exact $::star::rpt_types "verbose"] < 0} { 
                        set rptLnk [dict get $value "mode_stats" $mode "rpt_summary_lnk"]
		      } else {
                        set rptLnk [dict get $value "mode_stats" $mode "rpt_verbose_lnk"]
		      }	

                      #set rptSumLnkShortended [lindex [split $rptLnk "/"] end]
                      set rptLnkShortended [lindex [split $rptLnk "/"] end]

                      if {$fep > 0} {

	                puts $fp \
		          "[format "%10d %10.2f %15.2f   %-20s  %-20s  %-30s  %-40s" \
		            $fep $wns $tns $hierCat $rptLnkShortended $clkGrp $clkPair]"

                      } 
		    }
	          }
		}
              }		      
	    }
          }
	close $fp
	}
      }
    }
  }
}



proc ::star::writePyHandoff {} {

  set fp [open \
    "$::star::engineerViewDir/.star_tcl2py_miscInfo.yaml" w+]

  #miscInfo
  set curIndentLvl 0
  puts $fp \
    "[::star::indent $curIndentLvl]miscInfo:"

  incr curIndentLvl 2

  set userId [sh whoami]
  puts $fp \
    "[::star::indent $curIndentLvl]userid: $userId"

  foreach {key value} [array get ::nxvars] {
    puts $fp \
      "[::star::indent $curIndentLvl]$key: $value"
  }

  close $fp

  set fp [open \
    "$::star::engineerViewDir/.star_tcl2py_pvtInfo.yaml" w+]

  #pvtInfo
  set curIndentLvl 0
  puts $fp \
    "[::star::indent $curIndentLvl]pvtInfo:"

  incr curIndentLvl 2
  foreach modeGrp \
     [array names ::star::modeGrpClean] {
     
    puts $fp \
      "[::star::indent $curIndentLvl]$modeGrp:"

    incr curIndentLvl 2
    foreach mode $::star::modeGrpClean($modeGrp) {

      puts $fp \
        "[::star::indent $curIndentLvl]$mode:"
    }

    incr curIndentLvl -2
  }

  close $fp
  
  set fp [open \
    "$::star::engineerViewDir/.star_tcl2py_timingInfo.yaml" w+]

  # timingInfo
  set curIndentLvl 0
  puts $fp \
    "[::star::indent $curIndentLvl]timingInfo:"

  incr curIndentLvl 2
  dict for {modeGrp value} \
	     $::star::catTreeTiming {

    puts $fp \
      "[::star::indent $curIndentLvl]$modeGrp:"

    incr curIndentLvl 2
    dict for {delay value} $value {

      puts $fp \
	"[::star::indent $curIndentLvl]$delay:"

      incr curIndentLvl 2
      dict for {mainCat value} $value {

        puts $fp \
	  "[::star::indent $curIndentLvl]$mainCat:"

        incr curIndentLvl 2
	dict for {hierCat value} $value {

	  if {$hierCat eq "mode_stats"} {

	    puts $fp "[::star::indent $curIndentLvl]$hierCat:"

            incr curIndentLvl 2
	    dict for {mode value} $value {

	      puts $fp "[::star::indent $curIndentLvl]$mode:"

              incr curIndentLvl 2
	      dict for {key value} $value {

	        puts $fp "[::star::indent $curIndentLvl]$key: $value"

	      }
              incr curIndentLvl -2

	    }
            incr curIndentLvl -2

	  } else {

	    puts $fp "[::star::indent $curIndentLvl]$hierCat:"

            incr curIndentLvl 2
	    dict for {clkPair value} $value {

	      if {$clkPair eq "mode_stats"} {
	        puts $fp "[::star::indent $curIndentLvl]$clkPair:"

                incr curIndentLvl 2
	        dict for {mode value} $value {

	          puts $fp "[::star::indent $curIndentLvl]$mode:"

                  incr curIndentLvl 2
	          dict for {key value} $value {

	            puts $fp "[::star::indent $curIndentLvl]$key: $value"

	          }
                  incr curIndentLvl -2

	        }
                incr curIndentLvl -2

	      } else {

	        puts $fp "[::star::indent $curIndentLvl]$clkPair:"

                incr curIndentLvl 2
	        dict for {clkGrp value} $value {

		  set clkGrpMod [string trim $clkGrp "*"]

	          puts $fp "[::star::indent $curIndentLvl]$clkGrpMod:"

                  incr curIndentLvl 2
	          dict for {modeStats value} $value {

	            puts $fp "[::star::indent $curIndentLvl]$modeStats:"

                    incr curIndentLvl 2
	            dict for {mode value} $value {

	              puts $fp "[::star::indent $curIndentLvl]$mode:"

                      incr curIndentLvl 2
	              dict for {key value} $value {

	                puts $fp "[::star::indent $curIndentLvl]$key: $value"
	              }
                      incr curIndentLvl -2

	            }
                    incr curIndentLvl -2

	          }
                  incr curIndentLvl -2

	        }
                incr curIndentLvl -2

	      }

	    }
            incr curIndentLvl -2

          }

	}
        incr curIndentLvl -2

      }
      incr curIndentLvl -2

    }
    incr curIndentLvl -2

  }

  close $fp
}

proc ::star::processTpCol {modeGrp mode delay pathCol} {

  # Collection to hold the results
  array set ::star::starProcessedTpCol {}

  # Cannot use parallel_foreach_in_col in dmsa master
  # Can use parallel_foreach_in_col in single scenario mode
  # Cannot use parallel_foreach when we try to set an user attr
  foreach_in_collection tP $pathCol {

    set sPclass [get_attr \
          [get_attr $tP startpoint] object_class]
    set sPname  [get_attr \
          [get_attr $tP startpoint] full_name]
    set ePclass [get_attr \
          [get_attr $tP endpoint] object_class]
    set ePname  [get_attr \
          [get_attr $tP endpoint] full_name]

    set sH "uK" 
    if {$sPclass eq "pin"} { 
      foreach ele $::star::hierMapSorted {
	set hierShort [lindex [split $ele " "] 0]
	set hierPrefix [lindex [split $ele " "] 1]
	#puts "STAR> Debug : Comparing SP with hierarchy,"
	#puts "STAR> \t hierShort : $hierShort"
	#puts "STAR> \t hierPrefix : $hierPrefix"
        if {[regexp "^$hierPrefix" $sPname]} {
          set sH $hierShort
        }
      }
      if {$sH eq "uK"} {set sH "top"}
    } else {
      set sH "input"
    }

    set eH "uK";
    if {$ePclass eq "pin"} { 
      foreach ele $::star::hierMapSorted {
	set hierShort [lindex [split $ele " "] 0]
	set hierPrefix [lindex [split $ele " "] 1]
	#puts "STAR> Debug : Comparing EP with hierarchy,"
	#puts "STAR> \t hierShort : $hierShort"
	#puts "STAR> \t hierPrefix : $hierPrefix"
        if {[regexp "^$hierPrefix" $ePname]} {
          set eH $hierShort
        }
      }
      if {$eH eq "uK"} {
        set eH "top"
      }
    } else {
      set eH "output"
    }

    if {$sH ne "top" && \
          $sH ne "input" && \
            $eH ne "top" && \
              $eH ne "output" } {

      set starHierGrp "${sH}:${eH}"

      if {$sH eq $eH} {

        set starMainGrp "within_hm"

      } else {

        set starMainGrp "inter_hm"
      }

    } elseif {$sH eq "top" && \
               ($eH ne "top" && \
                  $eH ne "output")} {

       set starMainGrp "top:hm"
       set starHierGrp "${sH}:${eH}"

    } elseif {$sH eq "input" && \
               ($eH ne "top" && \
                  $eH ne "output")} {

       set starMainGrp "input:hm"
       set starHierGrp "${sH}:${eH}"

    } elseif {($sH ne "top" && \
                 $sH ne "input") && \
                   $eH eq "top"} {

       set starMainGrp "hm:top"
       set starHierGrp "${sH}:${eH}"

    } elseif {($sH ne "top" && \
                 $sH ne "input") && \
                   $eH eq "output"} {

       set starMainGrp "hm:output"
       set starHierGrp "${sH}:${eH}"

    } else {
       
       set starMainGrp "${sH}:${eH}"
       set starHierGrp "none"

    }

    set sPclock \
      [::star::attrDefined $tP startpoint_clock]

    set ePclock \
      [::star::attrDefined $tP endpoint_clock]

    #set sPclock [get_attr \
    #      [get_attr $tP startpoint_clock] full_name]
    #set ePclock [get_attr \
    #      [get_attr $tP endpoint_clock] full_name]

    # Note that the order of clock is reverse
    # EP clock followed by SP clock. This is to 
    # facilitate lsort based on EP clocks 
    set starClkPair "${ePclock}:${sPclock}"

    set pGrp [get_attr \
      [get_attr $tP path_group] full_name]
    set starPathGrp $pGrp

    # Assign paths to the collection
    set i $modeGrp
    lappend i $delay
    lappend i $mode
    lappend i $starMainGrp
    lappend i $starHierGrp
    lappend i $starClkPair
    lappend i $starPathGrp
    set key [join $i ","]
    append_to_col ::star::starProcessedTpCol($key) $tP

    ## Populate the index for future reference
    if {![dict exist $::star::timingIndex $modeGrp]} {
      dict set ::star::timingIndex $modeGrp {}
    }

    if {![dict exist $::star::timingIndex \
            $modeGrp $delay]} {
      dict set ::star::timingIndex \
              $modeGrp $delay {}
    }

    if {![dict exist $::star::timingIndex \
            $modeGrp $delay $starMainGrp]} {
      dict set ::star::timingIndex \
            $modeGrp $delay $starMainGrp {}
    }

    if {![dict exist $::star::timingIndex \
            $modeGrp $delay $starMainGrp $starHierGrp]} {
      dict set ::star::timingIndex \
            $modeGrp $delay $starMainGrp $starHierGrp {}
    }

    if {![dict exist $::star::timingIndex \
            $modeGrp $delay $starMainGrp \
                   $starHierGrp $starClkPair]} {

      dict set ::star::timingIndex \
            $modeGrp $delay $starMainGrp \
                   $starHierGrp $starClkPair [list $starPathGrp]

    } else {

      if {[lsearch -exact [dict get $::star::timingIndex \
                              $modeGrp $delay $starMainGrp \
		              $starHierGrp $starClkPair] \
		                $starPathGrp] < 0} {

        dict with ::star::timingIndex \
            $modeGrp $delay $starMainGrp \
                   $starHierGrp \
		   {lappend $starClkPair $starPathGrp}
      }

    }

    #dict lappend ::star::timingIndex \
    #  $modeGrp $delay $starMainGrp \
    #    $starHierGrp $starClkPair $starPathGrp

    #if {![dict exist $::star::timingIndex \
    #        $modeGrp $delay $starMainGrp \
    #               $starHierGrp $starClkPair $starPathGrp]} {
    #  dict set ::star::timingIndex \
    #        $modeGrp $delay $starMainGrp \
    #               $starHierGrp $starClkPair $starPathGrp {}
    #}

  }


}

proc ::star::popCatTreeTiming {} {

  dict create ::star::catTreeTiming {}

  set ::star::overviewTableIndex {
                          "top:top"   
                          "top:hm"    
                          "hm:top"    
                          "inter_hm"     
                          "within_hm"    
                          "input:top" 
                          "input:hm" 
                          "input:output" 
                          "hm:output" 
                          "top:output"}
 
  # Assign -->none<-- for mainCat which do not have
  # any hierCats
  dict for {modeGrp value} $::star::timingIndex {
    dict for {delay value} $value {
      dict for {mainCat value} $value {
        if {![dict exists \
  $::star::timingIndex $modeGrp $delay $mainCat]} {
          dict set ::star::timingIndex \
	    $modeGrp $delay $mainCat "none"	  
	}
      }
    }   
  } 

  #Overview table info -new
  foreach modeGrp [array names ::star::modeGrpClean] {

    foreach delay {"max" "min"} {

      set arrayKeys \
	  [array names ::star::modeGrpSceneMap \
		   -regexp "$modeGrp,.+,$delay"]

      if {$::star::debug} {
        puts "STAR> Debug: Attempting to popCatTree for "
	puts "STAR>\t $modeGrp"
	puts "STAR>\t $delay"
      }

      if {[llength $arrayKeys]} {

        if {$::star::debug} {
          puts "STAR> Debug: Access granted to popCatTree for "
          puts "STAR>\t $modeGrp"
          puts "STAR>\t $delay"
        }

        foreach mainCat $::star::overviewTableIndex {

	  set arrayKeys \
	    [array names ::star::modeGrpSceneMap \
	         -regexp "$modeGrp,.+,$delay"]

          set modes {}
          foreach key $arrayKeys {
            lappend modes [lindex [split $key ","] 1]
          }

	  if {$::star::debug} {
	    puts "STAR> Debug: Iterating for modes $modes"
	  }

	  foreach mode $modes {

	    set arrayKeys [array names \
                           ::star::starProcessedTpCol \
	    -regexp "$modeGrp,$delay,${mode},${mainCat},.+"]

            if {[llength $arrayKeys]} {

              set pathCol ""
              foreach key $arrayKeys {
		#puts "debug: adding to pathCol ::star::starProcessedTpCol($key)"

                append_to_col pathCol \
	          $::star::starProcessedTpCol($key)
              }

              set fep [sizeof_col $pathCol]

	      if {$fep} {
                set wns \
  [expr min([regsub -all " " [get_attr $pathCol slack] ","])]
                set tns \
  [::tcl::mathop::+ {*}[split [get_attr $pathCol slack] " "]] 
              } else { 
	        set wns 0; set tns 0.0; set fep 0;
              }

	      dict set ::star::catTreeTiming \
  $modeGrp $delay $mainCat "mode_stats" $mode "wns" $wns
	      dict set ::star::catTreeTiming \
  $modeGrp $delay $mainCat "mode_stats" $mode "tns" $tns
	      dict set ::star::catTreeTiming \
  $modeGrp $delay $mainCat "mode_stats" $mode "fep" $fep

              if {$::star::debug} {
                puts "STAR> Debug: Successfully popCatTree for "
	        puts "STAR>\t $modeGrp"
	        puts "STAR>\t $delay"
	        puts "STAR>\t $mainCat"
              }

	    # No mode info clause
	    } else {

	      dict set ::star::catTreeTiming \
  $modeGrp $delay $mainCat "mode_stats" $mode "wns" 0 

	      dict set ::star::catTreeTiming \
  $modeGrp $delay $mainCat "mode_stats" $mode "tns" 0.0 

	      dict set ::star::catTreeTiming \
  $modeGrp $delay $mainCat "mode_stats" $mode "fep" 0 

              if {$::star::debug} {
                puts "STAR> Debug: Successfully null popCatTree for "
	        puts "STAR>\t $modeGrp"
	        puts "STAR>\t $delay"
	        puts "STAR>\t $mainCat"
              }
            }
	  }
	}

      } else {
        if {$::star::debug} {
          puts "STAR> Debug: Access rejected to popCatTree for "
          puts "STAR>\t $modeGrp"
          puts "STAR>\t $delay"
	  puts "STAR>\since, there is no valid scenarios."
	  puts "STAR> ::star::modeGrpSceneMap is,"
	  puts "STAR> \t [parray ::star::modeGrpSceneMap]"
        }
      }
    }
  }

  # Main cat summary table info -new
  foreach modeGrp [array names ::star::modeGrpClean] {

    foreach delay {"max" "min"} {

      set arrayKeys \
	  [array names ::star::modeGrpSceneMap \
		   -regexp "$modeGrp,.+,$delay"]

      if {[llength $arrayKeys]} {
        foreach mainCat $::star::overviewTableIndex {

          if {[dict exists \
  $::star::timingIndex $modeGrp $delay $mainCat]} {

	    dict for {hierCat value} \
  [dict get $::star::timingIndex $modeGrp $delay $mainCat] {
	      set arrayKeys [array names ::star::modeGrpSceneMap \
		-regexp "$modeGrp,.+,$delay"]
        
	      if {[llength $arrayKeys]} {
                set modes {}
                foreach key $arrayKeys {
                  lappend modes [lindex [split $key ","] 1]
                }

	        foreach mode $modes {
	          set arrayKeys [array names \
                    ::star::starProcessedTpCol \
                    -regexp \
  "$modeGrp,$delay,${mode},${mainCat},${hierCat},.+"]

                  if {[llength $arrayKeys]} {
                    set pathCol ""
                    foreach key $arrayKeys {
                      append_to_col pathCol \
			$::star::starProcessedTpCol($key)
                    }
                    set fep [sizeof_col $pathCol]

	            if {$fep} {
                      set wns \
  [expr min([regsub -all " " [get_attr $pathCol slack] ","])]
                      set tns \
  [::tcl::mathop::+ {*}[split [get_attr $pathCol slack] " "]] 
                    } else { 
		      set wns 0; set tns 0.0;
	            }

                    dict set ::star::catTreeTiming \
  $modeGrp $delay $mainCat $hierCat "mode_stats" $mode "wns" $wns
	            dict set ::star::catTreeTiming \
  $modeGrp $delay $mainCat $hierCat "mode_stats" $mode "tns" $tns
	            dict set ::star::catTreeTiming \
  $modeGrp $delay $mainCat $hierCat "mode_stats" $mode "fep" $fep

	          } else {

	            dict set ::star::catTreeTiming \
  $modeGrp $delay $mainCat $hierCat "mode_stats" $mode "wns" 0 
	            dict set ::star::catTreeTiming \
  $modeGrp $delay $mainCat $hierCat "mode_stats" $mode "tns" 0.0 
	            dict set ::star::catTreeTiming \
  $modeGrp $delay $mainCat $hierCat "mode_stats" $mode "fep" 0 
                  }
		}
              }
	    }
	  } 
	}
      }
    }
  }

  # Main cat with hierCat -new
  set filePointerNum 1
  foreach modeGrp [array names ::star::modeGrpClean] {

    foreach delay {"max" "min"} {
      set arrayKeys \
	  [array names ::star::modeGrpSceneMap \
		   -regexp "$modeGrp,.+,$delay"]

      if {[llength $arrayKeys]} {
        foreach mainCat $::star::overviewTableIndex {

          if {[dict exists \
  $::star::timingIndex $modeGrp $delay $mainCat]} {

	    set arrayKeys [array names \
                ::star::starProcessedTpCol \
                -regexp \
	      "$modeGrp,$delay,${mode},${mainCat},.+"]

	    dict for {hierCat value} \
 [dict get $::star::timingIndex $modeGrp $delay $mainCat] {

	      set arrayKeys [array names ::star::modeGrpSceneMap \
		-regexp "$modeGrp,.+,$delay"]

	      dict for {clkPair clkGrps} $value {
	        set arrayKeys \
		  [array names ::star::modeGrpSceneMap \
	          -regexp "$modeGrp,.+,$delay"]

	        if {[llength $arrayKeys]} {

                  set modes {}
                  foreach key $arrayKeys {
                    lappend modes \
		      [lindex [split $key ","] 1]
                  }

                  foreach clkGrp $clkGrps {


	            foreach mode $modes {

	              set key \
  "$modeGrp,$delay,$mode,$mainCat,$hierCat,$clkPair,$clkGrp"

                      if {[info exist \
		             ::star::starProcessedTpCol($key)]} {

                        set pathCol \
		          $::star::starProcessedTpCol($key)

                        set fep [sizeof_col $pathCol]

                        set wns \
  [expr min([regsub -all " " [get_attr $pathCol slack] ","])]

                        set tns \
  [::tcl::mathop::+ {*}[split [get_attr $pathCol slack] " "]] 

                      } else { 

		        set wns 0.0; set tns 0.0; set fep 0

	              }

                      dict set ::star::catTreeTiming \
             $modeGrp $delay $mainCat $hierCat $clkPair \
             $clkGrp "mode_stats" $mode "wns" $wns

                      dict set ::star::catTreeTiming \
             $modeGrp $delay $mainCat $hierCat $clkPair \
             $clkGrp "mode_stats" $mode "tns" $tns

                      dict set ::star::catTreeTiming \
             $modeGrp $delay $mainCat $hierCat $clkPair \
             $clkGrp "mode_stats" $mode "fep" $fep


                      #set wnsPath [index_col $pathCol 0]

		      #set sP [get_object_name \
		      #      [get_attr $wnsPath startpoint]]

		      #set eP [get_object_name \
	              #      [get_attr $wnsPath endpoint]]

		      if {$::star::v_tool_mode eq "primetime_master"} {

                        set targetScenarios \
                          $::star::modeGrpSceneMap($modeGrp,$mode,$delay)

                        current_scenario $targetScenarios

                      }

		      #set realFileName [lindex [split $var_rpt_wns "/"] end]


     
                      set ePcoll [get_object_name \
			      [get_attr $pathCol endpoint]]

		      if {$delay eq "max"} {
		        set slack_lt $::star::v_rpt_setup_slack_lt
                        set nworst $::star::timing_setup_nworst
		      } else {
		        set slack_lt $::star::v_rpt_hold_slack_lt
                        set nworst $::star::timing_hold_nworst
		      }

                      redirect -var null {

		        set nwPathCol \
                          [get_timing_path \
		                -delay_type $delay \
		                -to $ePcoll \
		                -group $clkGrp \
                                -nworst $nworst \
		                -max_paths 2000000 \
		                -pba_mode $::star::timing_pba_mode]

                      }

                      set nvp [sizeof_col $nwPathCol]

                      set nwTns \
  [::tcl::mathop::+ {*}[split [get_attr $nwPathCol slack] " "]] 

	              dict set ::star::catTreeTiming \
             $modeGrp $delay $mainCat $hierCat $clkPair \
             $clkGrp "mode_stats" $mode "nvp" $nvp

	              dict set ::star::catTreeTiming \
             $modeGrp $delay $mainCat $hierCat $clkPair \
             $clkGrp "mode_stats" $mode "nwTns" $nwTns

                      foreach var_rpt_typ $::star::rpt_types {

		        # Sometimes the links of previous STAR out directory
		        # is not cleanly removed. So keep incrementing the file
		        # numbers until we find a unused fileNumber
		        while {[file exists \
		          $::star::engineerViewDir/rpt${filePointerNum}]} {
		          incr filePointerNum
		        }


			if {$var_rpt_typ eq "verbose"} {

                          #set var_rpt_verbose \
  "$::star::engineerViewDir/$mode.$mainCat.$hierCat.$clkPair.$clkGrp.tns.$delay.rpt"
                          set var_rpt_verbose \
			    "$::star::engineerViewDir/rpt${filePointerNum}"

                          redirect -file $var_rpt_verbose {

		            report_timing \
		                  -delay_type $delay \
		                  -to $ePcoll \
		                  -group $clkGrp \
		                  -pba_mode $::star::timing_pba_mode \
		                  -slack_lesser_than $slack_lt \
		                  -max_paths $::star::verbose_rpt_max_paths \
		                  -path_type full_clock_exp \
		                  -nosplit \
		                  -voltage \
		                  -include_hierarchical_pins \
		                  -transition_time \
		                  -capacitance \
		                  -derate \
		                  -crosstalk_delta \
		                  -input_pins \
		                  -nets \
		                  -exceptions all 
	                  }

	                  dict set ::star::catTreeTiming \
                 $modeGrp $delay $mainCat $hierCat $clkPair \
                 $clkGrp "mode_stats" $mode "rpt_verbose" $var_rpt_verbose

	                  dict set ::star::catTreeTiming \
                 $modeGrp $delay $mainCat $hierCat $clkPair \
                 $clkGrp "mode_stats" $mode "rpt_verbose_lnk" \
	         $::star::engineerViewDir/rpt${filePointerNum}

                        }

			if {$var_rpt_typ eq "summary"} {

                          #set var_rpt_summary \
  "$::star::engineerViewDir/$mode.$mainCat.$hierCat.$clkPair.$clkGrp.wns.$delay.rpt"
                          set var_rpt_summary \
   			    "$::star::engineerViewDir/rpt${filePointerNum}"

                          redirect -file $var_rpt_summary {

		            report_timing \
		                  -delay_type $delay \
		                  -to $ePcoll \
		                  -group $clkGrp \
		                  -pba_mode $::star::timing_pba_mode \
		                  -slack_lesser_than $slack_lt \
		                  -max_paths $::star::verbose_rpt_max_paths \
		                  -path_type summary \
		                  -nosplit 
	                  }

	                  dict set ::star::catTreeTiming \
                 $modeGrp $delay $mainCat $hierCat $clkPair \
                 $clkGrp "mode_stats" $mode "rpt_summary" $var_rpt_summary

	                  dict set ::star::catTreeTiming \
                 $modeGrp $delay $mainCat $hierCat $clkPair \
                 $clkGrp "mode_stats" $mode "rpt_summary_lnk" \
	         $::star::engineerViewDir/rpt${filePointerNum}

                        }

		      }	

		      #set realFileName [lindex [split $var_rpt_verbose "/"] end]


		      #redirect -var null {
		      #  file link -symbolic \
		      #    "$::star::engineerViewDir/rpt${filePointerNum}" \
		      #        $realFileName
	              #}

		      #if {[regexp {Error} $null]} {
		      #  puts "STAR> Error: Unable to soft link this file"
		      #  puts "STAR> -->$::star::engineerViewDir/rpt${filePointerNum}<--"
		      #  puts "STAR> to -->$var_rpt_verbose<--" 
		      #}


		      # Sometimes the links of previous STAR out directory
		      # is not cleanly removed. So keep incrementing the file
		      # numbers until we find a unused fileNumber
		      #while {[file exists \
		      #  $::star::engineerViewDir/rpt${filePointerNum}]} {
		      #  incr filePointerNum
		      #}

                      #set var_rpt_fep \
  "$::star::engineerviewdir/$mode.$maincat.$hiercat.$clkpair.$clkgrp.fep.$delay.rpt"
                      #set var_rpt_fep \
			"$::star::engineerViewDir/rpt${filePointerNum}"

                      #redirect -file $var_rpt_fep {

		      #  report_timing $pathCol \
		      #       -path_type summary \
		      #       -nosplit

	              #}


		      #redirect -var null {
		      #  file link -symbolic \
		      #    "$::star::engineerViewDir/rpt${greatestRptNum}.gz" \
		      #        $var_rpt_fep
	              #}

		      #set realFileName [lindex [split $var_rpt_fep "/"] end]

		      #redirect -var null {
		      #  file link -symbolic \
		      #    "$::star::engineerViewDir/rpt${greatestRptNum}.gz" \
		      #        $realFileName
	              #}
		      #redirect -var null {
		      #  file link -symbolic \
		      #    "$::star::engineerViewDir/rpt${filePointerNum}" \
		      #        $realFileName
	              #}

		      #if {[regexp {Error} $null]} {
		      #  puts "STAR> Error: Unable to soft link this file"
		      #  puts "STAR> -->$::star::engineerViewDir/rpt${filePointerNum}<--"
		      #  puts "STAR> to -->$var_rpt_fep<--" 
		      #}

	              #dict set ::star::catTreeTiming \
             $modeGrp $delay $mainCat $hierCat $clkPair \
             $clkGrp "mode_stats" $mode "rpt_fep" $var_rpt_fep

	              #dict set ::star::catTreeTiming \
             $modeGrp $delay $mainCat $hierCat $clkPair \
             $clkGrp "mode_stats" $mode "rpt_fep_lnk" \
             $::star::engineerViewDir/rpt${filePointerNum}

		      #incr filePointerNum

                    }
                  }
		}
	      }
	    }
	  }
	}
      }
    }
  }
}


proc ::star::callStarPy {} {

  puts "Calling STAR.py"
  exec /pkg/OSS-python-/3.9.13/x86_64-linux/bin/python3 \
	  $::star::resourceDir/star.py \
	  "pub" \
	  $::star::engineerViewDir

}


#------------------------------------------------
# Main procedure
#------------------------------------------------
proc ::star::main {} {
  
  ::star::printBanner	
  ::star::envCheck

  set ::star::resourceDir [file normalize \
                 [file dirname [info script]]]

  #set resourceCheckOk [::star::checkResources]

  #::star::parseArgs
  #if {$resourceCheckOk} 
  if {1} {
    ::star::readConfig
    #puts $::star::config

    set ::star::goodInputs [::star::validateInputs]
    if {$::star::v_flow_name eq "nxcode"} {
      set ::star::goodShell [::star::extractNxVars]
    } elseif {$::star::v_flow_name eq "lynx"} {
      if {$::star::debug} {
        puts "STAR> Attempting to extractLynxVars"
      }
      set ::star::goodShell [::star::extractLynxVars]
    }
  
    set ::star::goodEnv 1
    set ::star::engineerViewDir \
	    "$::star::unixOutDir/eview"
    set ::star::managementViewDir \
	    "$::star::unixOutDir/mview"

    if {[catch \
          {file mkdir $::star::engineerViewDir}]} {
      puts -nonewline "STAR> Error : Unable to create output "
      puts -nonewline "directory -->$::star::engineerViewDir<--"
      puts " Please check for write permissions."
      set ::star::goodEnv 0
    }

    if {[catch \
          {file mkdir $::star::managementViewDir}]} {
      puts -nonewline "STAR> Error : Unable to create output "
      puts -nonewline "directory -->$::star::managementViewDir<--"
      puts " Please check for write permissions."
      set ::star::goodEnv 0
    }

    catch {
      file delete -force $::star::engineerViewDir/*
      file delete -force $::star::managementViewDir/*
    }


  } else {
    set ::star::goodInputs 0
    set ::star::goodShell 0
    set ::star::goodEnv 0
  }

  if {$::star::goodInputs && \
        $::star::goodShell && \
          $::star::goodEnv} {


    #puts "STAR> Scenarios valid in this shell are..."
    #puts "\t [parray ::star::modeGrpSceneMap]"

    set ::star::catTreeTiming [dict create]
    set ::star::timingIndex [dict create]
    if {$::star::v_tool_name eq "pt_shell"} {
      if {$::star::v_tool_mode eq "primetime" || \
        $::star::v_tool_mode eq "primetime_slave"} {
          
        # We should warn user if the max_paths count is huge
        foreach modeGrp [array names ::star::modeGrpClean] {
          foreach mode $::star::modeGrpClean($modeGrp) {
            foreach delay {"max" "min"} {
	      if {$::star::debug} {
	        puts -nonewline "STAR> Debug: Attempting "
	        puts " reporting for"
	        puts "\t modeGrp : $modeGrp"
	        puts "\t mode    : $mode"
	        puts "\t delay   : $delay"
		puts "\t modeGrpSceneMap : "
		puts "\t[parray ::star::modeGrpSceneMap]"
	      }
              if {[info exists \
  ::star::modeGrpSceneMap($modeGrp,$mode,$delay)]} {
	        if {1} {
		  puts -nonewline "STAR> Gathering "
		  puts "timing paths for,"
		  puts "\t modeGrp : $modeGrp"
		  puts "\t mode    : $mode"
		  puts "\t delay   : $delay"
		}

		if {$delay eq "max"} {
		  set slack_lt $::star::v_rpt_setup_slack_lt
		  set max_paths $::star::v_rpt_setup_max_paths
		} else {
		  set slack_lt $::star::v_rpt_hold_slack_lt
		  set max_paths $::star::v_rpt_hold_max_paths
		}

		redirect -var null {

		  set pathCol {}

		  foreach var_path_type $::star::v_rpt_path_types {

                    append_to_col pathCol \
                      [get_timing_path \
		         -max_paths $max_paths \
                         -slack_lesser $slack_lt \
            	         -delay_type $delay \
		         -pba_mode $::star::timing_pba_mode \
			 -start_end_type $var_path_type \
		         -path_type full_clock_exp]

		  }

	        }

		if {![regexp {Error} $null]} {


		  if {$::star::debug} {

                    set pathColSize [sizeof_col $pathCol]
		    puts "STAR> Debug: pathcol size : $pathColSize"

		  }

                  ::star::processTpCol \
			  $modeGrp \
			  $mode \
			  $delay \
			  $pathCol

                  ::star::popCatTreeTiming
                  ::star::writePyHandoff
	          ::star::callStarPy
	          ::star::writeTxtIndex

		} else {

		  set ::star::goodOnPathsCol 0
		  puts "STAR> Error: Could not collect FEPs for"
		  puts "\t modeGrp : $modeGrp"
		  puts "\t mode    : $mode"
		  puts "\t delay   : $delay"

                  puts "STAR> Debug: cmd --> get_timing_path"
		  puts "\t -max_paths $max_paths "
                  puts "\t -slack_lesser $slack_lt "
            	  puts "\t -delay_type $delay "
		  puts "\t -pba_mode $::star::timing_pba_mode "
		  puts "\t -path_type full_clock_exp"

		}
	      }
	    }
	  }
	}

      } elseif {$::star::v_tool_mode eq "primetime_master"} {

        current_scenario -all
        foreach modeGrp [array names ::star::modeGrpClean] {
          foreach mode $::star::modeGrpClean($modeGrp) {
            foreach delay {"max" "min"} {

	      if {$::star::debug} {
	        puts -nonewline "STAR> Debug: Attempting "
	        puts " reporting for"
	        puts "\t modeGrp : $modeGrp"
	        puts "\t mode    : $mode"
	        puts "\t delay   : $delay"
		puts "\t modeGrpSceneMap : "
		puts "\t[parray ::star::modeGrpSceneMap]"
	      }

              if {[info exists \
  ::star::modeGrpSceneMap($modeGrp,$mode,$delay)]} {

	        if {$::star::debug} {

		  puts -nonewline "STAR> Debug: Gathering "
		  puts "timing paths for,"
		  puts "\t modeGrp : $modeGrp"
		  puts "\t mode    : $mode"
		  puts "\t delay   : $delay"

		}
                set targetScenarios \
                  $::star::modeGrpSceneMap($modeGrp,$mode,$delay)
                current_scenario $targetScenarios

		if {$delay eq "max"} {
		  set slack_lt $::star::v_rpt_setup_slack_lt
		  set max_paths $::star::v_rpt_setup_max_paths
		} else {
		  set slack_lt $::star::v_rpt_hold_slack_lt
		  set max_paths $::star::v_rpt_hold_max_paths
		}

                # We should warn user if the max_paths count is huge
		redirect -var null {

		  set pathCol {}

		  foreach var_path_type $::star::v_rpt_path_types {

                    append_to_col pathCol \

                      [get_timing_path \
		       -max_paths $max_paths \
                       -slack_lesser $slack_lt \
                       -delay_type $delay \
		       -pba_mode $::star::timing_pba_mode \
		       -path_type full_clock_exp \
		       -start_end_type $var_path_type \
                       -attributes { \
                       startpoint \
                       startpoint_clock \
                       endpoint \
                       endpoint_clock \
                       path_group \
                       slack}]

	          }

		}

		if {![regexp {Error} $null]} {

		  if {$::star::debug} {

                    set pathColSize [sizeof_col $pathCol]
		    puts "STAR> Debug: pathcol size : $pathColSize"

		  }
                  ::star::processTpCol $modeGrp $mode $delay $pathCol

		} else {
		  set ::star::goodOnPathsCol 0
		  puts "STAR> Error: Could not collect FEPs for"
		  puts "STAR> \t [get_object_name $targetScenarios]"  
                }
              }
            }
          }
        }

        current_scenario -all
        ::star::popCatTreeTiming
	::star::writeTxtIndex
        ::star::writePyHandoff
	::star::callStarPy
        current_scenario -all

      }
    }



    puts "#----------------------------------"
    puts "STAR> Normal exit                  "
    puts "#----------------------------------"
  } else {
    ::star::exit_star
  }
}

::star::main
