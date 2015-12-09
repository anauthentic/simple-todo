package require Tcl 8.6
package require Tk
package require struct::tree
package require struct::list

set wdir [file dirname [info script]]
source [file join $wdir wiki_snippets.tcl]
namespace import snippets::lambda
source [file join $wdir callib.tcl]

proc tkmsg {msg} { tk_messageBox -message $msg }

namespace eval settings {
    set path [file join $::wdir data data.scheduler]
    set note_frame_width 140
    set rce_buttons_font {Helvetica 11 bold}    ;#remove/complete/edit buttons

    set note_font {Helvetica 9 bold}
    set note_fg #FCAF3E
    set note_length 18

    set complete_note_font {Helvetica 9}
    set complete_note_fg #8AE235
    set label_complete_fg_1 #FCAF3E
    set label_complete_fg_0 #7CE235
    set label_edit_fg_1 #555753
    set label_edit_fg_0 #538FCF

    set months_font {Helvetica 14 bold}
    set daylabel_fg #FF6341

    # PARAMETERS
    set background #2E3436
    set clickedcolor black

    set main_obj {}                             ;#MAIN object name
}

namespace eval global_params {
    set edit_note_entrys {}
    set widgets_utime {}
}

set scheduler_data {}

oo::class create MAIN {}
oo::define MAIN {
    variable all_files calendar
    variable scheduler_data_path
    constructor {} {
        set scheduler_data_path $::settings::path
        set ::settings::main_obj [self namespace]
        set ::month_and_year [clock format [clock sec] -format "%B %Y" -locale ru]
        frame .frame -background #2E3436 -relief flat
        set topframe [ frame .frame.topframe -background #2E3436 ]
        button .frame.exit -text exit -command "[self namespace]::my _saveSchedulerData; destroy ."
        set calendar [ calwid .frame.calendar -font { helvetica 10 bold } \
            -dayfont {Arial 12 bold} \
            -background #2E3436 \
            -foreground #FCAF3E \
            -daylabel_foreground #FF6341 \
            -activebackground #454545 \
            -startsunday 0 \
            -delay 0 \
            -daynames {Воскресенье Понедельник Вторник Среда Четверг Пятница Суббота} \
            -month [clock format [clock sec] -format "%N"] \
            -year [clock format [clock sec] -format "%Y" ] \
            -balloon 1 \
            -relief groove ]

        set top_btn_style {-font {{Segoe Print} 24 bold} -background #2E3436 -foreground #AD7FA8}
        label $topframe.decyear -text "<<" {*}$top_btn_style
        label $topframe.decmonth -text "<" {*}$top_btn_style
        label $topframe.incrmonth -text ">" {*}$top_btn_style
        label $topframe.incryear -text ">>" {*}$top_btn_style
        label $topframe.monthyrlbl -textvariable ::month_and_year \
            -background #2E3436 -foreground #729FCF -font {Helvetica 14 bold} -width 20

        bind $topframe.decyear <Button-1> "[self namespace]::my decrementYear"
        bind $topframe.decmonth <Button-1> "[self namespace]::my decrementMonth"
        bind $topframe.incrmonth <Button-1> "[self namespace]::my incrementMonth"
        bind $topframe.incryear <Button-1> "[self namespace]::my incrementYear"


        pack .frame -side top -expand 1 -fill both
        pack $topframe -pady 3
        pack $topframe.decyear    -side left -padx 30 -pady 3
        pack $topframe.decmonth   -side left -padx 3 -pady 3
        pack $topframe.monthyrlbl -side left -padx 3 -pady 3
        pack $topframe.incrmonth  -side left -padx 3 -pady 3
        pack $topframe.incryear   -side left -padx 30 -pady 3
        pack $calendar   -side top -anchor c  -expand 1 -padx 10
        pack .frame.exit -side bottom -anchor c -fill x -pady 3
        ########
        #my loadAndParseDirectories $::path
        #my fillCalendarWidgetFromDirectory
        my fillCalendarWidgetFromScheduler True
        wm protocol . WM_DELETE_WINDOW {MAIN destroy}
        wm title . {just todo}
    }

    destructor {
        my _saveSchedulerData
        exit
    }

    method _loadSchedulerData {} {
        if { ![catch {open $scheduler_data_path r} f] } {
            set res [read $f]; close $f
        } {
            if { ![catch {open $scheduler_data_path w} f] } {
                set res {}; close $f
            } { error {Unable to read or create settings file} }
        }
        set ::scheduler_data $res
        set ::read_scheduler_data_success 1
    }

    method _saveSchedulerData {} {
        if { [catch {set ::read_scheduler_data_success}] } {return}
        catch {file copy -force $scheduler_data_path $scheduler_data_path-bak}
        if { ![catch {open $scheduler_data_path w} f] } {
                puts $f $::scheduler_data
                close $f
            } { error {Unable to read or create settings file} }
    }

    method fillCalendarWidgetFromScheduler {{loadFromFile False} {onlyMarks False}} {
        if { $loadFromFile eq True } {my _loadSchedulerData}
        if { $onlyMarks eq False } {
            $calendar clearWidgets $calendar
            set ::scheduler_data [lsort -integer -stride 2 -index 0 $::scheduler_data]
        }
        $calendar clearMarks
        set i 0
        dict for {utime data} $::scheduler_data {
            scan [clock format $utime -format "%Y-%m-%d-%H%M%S"] {%d-%d-%d} Y m d
            foreach {iscompleted note} $data {}
            $calendar configure -mark "$d $m $Y $i red {$utime $iscompleted {$note}}"
            incr i
        }
    }

    ### BUILD DIRECTORIES TREE RECURSIVELY. UNUSED FOR NOW.////////
    # method loadAndParseDirectories {path} {
    #     #upvar $var all_files
    #     catch {::all_files destroy}
    #     struct::tree ::all_files
    #     set dirs [glob -directory $path -type d -nocomplain {[0-9][0-9][0-9][0-9]_[0-9][0-9]_[0-9][0-9]}]
    #     #set dirs [glob -directory $path -type d -nocomplain *]
    #     set ::recur_get_files [\
    #         lambda {dir node} \
    #         {
    #             foreach elem [glob -directory $dir -nocomplain *] {
    #                 set child [::all_files insert $node end]
    #                 ::all_files set $child path $elem
    #                 ::all_files set $child name [lindex [file split $elem] end]
    #                 if {[file isdirectory $elem]} \
    #                     {{*}$::recur_get_files $elem $child} \
    #                     {::all_files set $child filesize [file size $elem]}
    #             }
    #         }\
    #     ]
    #     foreach d $dirs {
    #         set node [::all_files insert root end $d]
    #         {*}$::recur_get_files $d $node
    #     }
    # }

    # method fillCalendarWidgetFromDirectory {} {
    #     foreach r_node [::all_files children root] {
    #         scan [lindex [file split $r_node] end] {%4[0-9]_%i_%i} Y m d
    #         set priority 0
    #         foreach c_node [::all_files children $r_node] {
    #             set path {}
    #             dict set path full_path "{[::all_files get $c_node path]}"
    #             dict set path cutted_path "{[string range [::all_files get $c_node path] [string length $::path] end]}"
    #             $calendar configure -mark "$d $m $Y $priority {red} {$path}"
    #             incr priority
    #         }
    #     }
    # }
    ### ////// BUILD DIRECTORIES TREE RECURSIVELY. UNUSED FOR NOW.

    method setMonthYear { } {
      set p [ $calendar configure -month ]
      set y [ $calendar configure -year ]
      set scanStr [format "%s/1/%s 12:00:00"  $p $y ]
      set timestamp [ clock scan $scanStr ]
      set ::month_and_year [clock format $timestamp -format "%B %Y" -locale ru]
    }

    method incrementMonth {} {
      $calendar nextmonth
      my setMonthYear
    }
    method decrementMonth {} {
      $calendar prevmonth
      my setMonthYear
    }
    method incrementYear {} {
      $calendar nextyear
      my setMonthYear
    }
    method decrementYear {} {
      $calendar prevyear
      my setMonthYear
    }
}

MAIN create main
main setMonthYear