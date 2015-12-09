package provide callib 0.3

# provides api for creating calendar widgets #
proc calwid args {
    set newWidget [callib::MakecalendarWid {*}$args]
    set newCmd "[
        list [namespace current]::callib::calproc] [list $newWidget] {*}\$args"
    proc $newWidget args $newCmd
    return $newWidget
} ;# END calwid

namespace eval callib {
    namespace eval snipp {}
    variable calState
    set calState(unique) 0
}

proc callib::snipp::makeNoteLabel {note_label_widget note iscompleted grid_row {utime 0}} {
    if { [winfo exists $note_label_widget] } {return}
    label $note_label_widget -text $note                      \
        -width $::settings::note_length                       \
        -bg $::settings::background                           \
        -highlightbackground $::settings::background          \
        -font [expr {$iscompleted ?                           \
                    $::settings::complete_note_font :         \
                    $::settings::note_font} \
        ]                                                     \
        -justify left -anchor w                               \
        -wraplength [expr {$::settings::note_frame_width-5}]  \
        -foreground [expr {$iscompleted ?                     \
                        $::settings::complete_note_fg :       \
                        $::settings::note_fg} \
        ]
    grid $note_label_widget -row $grid_row -column 4 -sticky w -pady 1 -padx 3
    # put utime in tags dict
    if {$utime eq 0} {return}
    dict set ::global_params::widgets_utime [winfo name $note_label_widget] $utime
}

proc callib::snipp::getKeys4Day {day} {
    set d [ dict filter $::scheduler_data script {k v} \
            {expr {[clock format $k -format "%e"] eq $day}} ]
}

proc callib::MakecalendarWid args {
    variable calState
    #make unique name per default
    set holder .calwid_$calState(unique)
    incr calState(unique)
    #if a window name was given on the command line then use it
    #overwriting the already computed name
    if {[string first . [lindex $args 0]] == 0} {
        # put the wanted name in holder
        set holder [lindex $args 0] 
        # remove the name from args
        set args [lreplace $args 0 0]
      };# END window path given

    #make defaults for the command line args

    #year
    set calState($holder.year) [clock format [clock scan now] -format %Y]

    #month
    set mon_num [clock format [clock scan now] -format %m]

    #month starts with 0, can be interpreted as octal ->remove leading 0
    set mon_num [string trimleft $mon_num 0]
    set calState($holder.month) $mon_num 

    #week starts on sunday in the us and on monday in germany
    set calState($holder.startsunday) 0

    #font defaults
    set calState($holder.font) {Lucidatypewriter 12 normal}

    #day names, change the defaults to the language needed
    set calState($holder.daynames) {So Mo Di Mi Do Fr Sa}

    #day font
    set calState($holder.dayfont) {Lucidatypewriter 12 bold}

    #command registered as callback
    set calState($holder.callback) {} 

    # marking list for days, a mark is a list containing a date
    # a mark priority and a mark color, if one day has multiple marks
    # the color of the highest priority is shown, if balloons are enabled
    # then all the marks texts in descending prio order are shown.
    # the list is {day month year prio color label}
    set calState($holder.mark) {}

    # this list contains the marks for the shown month
    set calState($holder.shownmarks) {}

    # last clicked gets row col address of the last clicked button
    set calState($holder.clicked) {}

    # last clicked gets the color of clicked
    set calState($holder.clickedcolor) "yellow"

    # default background goes here, as a default rootwindows background
    # is used
    set calState($holder.background) [. cget -background]

    # the default active background goes here, white
    set calState($holder.activebackground) "white"

    # progcallback: if set to 1, setting clicked will invoke callback
    #               if set to 0, setting clicked will not invoke callback
    # defaults to 1
    set calState($holder.progcallback) 1

    # balloons containing the mark texts, 1 enabled, 0 disables
    set calState($holder.balloon)      1

    # set the delay for the balloon here
    set calState($holder.delay)     1000

    # set the relief 
    set calState($holder.relief)    groove

    # set the relief 
    set calState($holder.foreground)    black

    set calState($holder.daylabel_foreground) black

    # check whether options are valid
    foreach {opt val} $args {
        # get rid of leading -
        set option [string range $opt 1 end] 
        if {![info exists calState($holder.$option)]} {
            # create oklist containing the possible commands
            regsub -all $holder. [
                array names calState $holder.*] {} oklist
            error "Bad Option, '$option'\n Valid options are $oklist"
        };# END: if option not in the calendar state array
        set calState($holder.$option) $val
    };# END: foreach option value pair

    # make a frame to hold it all. Declare the class as being Calendar
    frame $holder -class Calendar 
    # make the frames innards
    Draw $holder
    # rename the frame to give the widget the name $holder
    uplevel #0 [list rename $holder $holder.fr]
    #call the update procedure to use configuration options given at start
    update_cal  $holder
    bind $holder <Destroy> +[list rename $holder {}]
    # return the name of the new widget
    return $holder
};# END MakecalendarWid

proc callib::Draw parent {
    variable calState

    # make the weekday list
    set weekdays $calState($parent.daynames)
    if {$calState($parent.startsunday) != 1} {
        set weekdays [roll_left $weekdays]
    };# END if not start on sunday -> start on monday 
    # make labels for the days header
    set colcount 0
    foreach day $weekdays {
        set daylabel $parent.$colcount
        label $daylabel -justify center
        grid  $daylabel -row 1 -column $colcount -pady 10 -padx 5 -sticky w
        incr colcount
    };#END: foreach day in weekday 
    # get monthlist according to startsunday variable
    set month $calState($parent.month)
    set year  $calState($parent.year)
    set monthlist [cal_list_month $month \
                                  $year  \
                                  $calState($parent.startsunday) ]
    # make the buttons for the calendar, buttons needed 
    # as there will be commands associated with them
    # was button, switched to labels bacause buttons look 
    # ugly under Aqua, callbacks & activebackground implemented 
    # via bind

    for {set row 0} {$row < 6} {incr row} {
        for {set col 0} {$col<7} {incr col} {
            set thisfr $parent.frame$col$row
            set create_note_frame $thisfr.create_note_frame
            set create_note_label $create_note_frame.add_note
            set create_note_entry $create_note_frame.entry

            set add_note_command "callib::addNote $parent $thisfr.create_note_frame.entry $col$row; \
                                  $thisfr.create_note_frame.entry delete 0 end"
            #main frame
            frame $thisfr -width 100 -height 100 -bg $::settings::background \
                          -highlightbackground $::settings::background
            label $thisfr.main_label -highlightthickness 2
            frame $thisfr.note_frame -width $::settings::note_frame_width -highlightthickness 0
            frame $thisfr.complete_note_frame -width $::settings::note_frame_width -highlightthickness 0
            
            #create note frame
            frame $create_note_frame -highlightthickness 0 -bg $::settings::background \
                -highlightbackground $::settings::background
            label $create_note_label -text "+" -highlightthickness 1 \
                -bg $::settings::background -font $::settings::months_font \
                -fg $::settings::daylabel_fg
            entry $create_note_entry ;#-width $::settings::note_length
            #multientry::multientry $create_note_entry -maxheight 4 -parent $create_note_frame

            #edit note frame
            frame $thisfr.edit_note_frame -highlightthickness 0 \
                -bg $::settings::background \
                -highlightbackground $::settings::background

            #packing
            grid $create_note_label -row 0 -column 0 -padx 3 -sticky w
            grid $create_note_entry -row 0 -column 1 -sticky w
            grid $thisfr -padx 0 -pady 0 -ipadx 0 -ipady 0 -row [expr {$row+2}] -column $col -sticky nw
            grid $thisfr.main_label -row 0 -column 0 -sticky nw
            grid $thisfr.note_frame -row 1 -column 1 -sticky w
            grid $thisfr.complete_note_frame -row 2 -column 1 -sticky w

            bind $thisfr.create_note_frame.add_note <Button-1> $add_note_command
            bind $thisfr.create_note_frame.entry <Return> $add_note_command
            bind $thisfr.create_note_frame.entry <Escape> "$thisfr.create_note_frame.entry delete 0 end"
        };#END: col
    };#END: row
};# END: draw the widgets

proc callib::createWidgetsForOneNote {note_frame utime Mpri iscompleted} {
    variable calState
    set label_style "-highlightthickness 1 -bg $::settings::background \
        -font {$::settings::rce_buttons_font}"

    label $note_frame.label_remove$Mpri   -text \u00D7 {*}$label_style -foreground #FF6341
    label $note_frame.label_complete$Mpri -text \u2713 {*}$label_style \
        -foreground [set ::settings::label_complete_fg_$iscompleted]
    label $note_frame.label_edit$Mpri -text \u2710 {*}$label_style \
        -foreground [set ::settings::label_edit_fg_$iscompleted]

    grid $note_frame.label_remove$Mpri   -row $Mpri -column 0 -padx 1 -sticky w
    grid $note_frame.label_complete$Mpri -row $Mpri -column 1 -padx 0 -sticky w
    grid $note_frame.label_edit$Mpri     -row $Mpri -column 2 -padx 0 -sticky w

    bind $note_frame.label_remove$Mpri   <Button-1> \
        "callib::removeNote $note_frame $Mpri $utime"
    bind $note_frame.label_complete$Mpri <Button-1> \
        "callib::completeNote $note_frame.note$Mpri $utime"
    if {!$iscompleted} { 
        bind $note_frame.label_edit$Mpri <Button-1> "callib::editNote $note_frame $Mpri $utime" 
    }
}

#draw and bind widgets for clicked button
proc callib::activateButton {parent} {
    variable calState
    set tmp_dict {}
    set position [join $calState($parent.clicked) {}]
    set win $parent.frame$position.main_label
    set note_frame $parent.frame$position.note_frame
    set complete_note_frame $parent.frame$position.complete_note_frame
    set create_note_frame "$parent.frame$position.create_note_frame"

    grid configure $note_frame -column 0 -columnspan 1
    grid configure $complete_note_frame -column 0 -columnspan 1
    #grid $create_note_frame -row 0 -column 1 -sticky w
    place $create_note_frame -in $parent.frame$position.main_label -relx 1 -x 13
    focus $create_note_frame.entry
    #grid $edit_note_frame -row 1 -column 0 -pady 3

    # foreach {k v} [callib::snipp::getKeys4Day [$win cget -text]] {
    #     foreach {iscompleted note} $v {}
    #     createWidgetsForOneNote [expr {$iscompleted ? $complete_note_frame : $note_frame}] \
    #                             $utime \
    #                             $Mpri \
    #                             $iscompleted
    # }
    
    foreach Mlist $calState($parent.shownmarks) {
        foreach {Mday Mmonth Myear Mpri Mcol Mlabel} $Mlist {}
        foreach {utime _ _} $Mlabel {}
        #set utime [dict get $::global_params::widgets_utime ]
        foreach {iscompleted note} [dict get $::scheduler_data $utime] {}
        if {($Mday == [string trim [$win cget -text]])} {
            createWidgetsForOneNote [expr {$iscompleted ? $complete_note_frame : $note_frame}] \
                                    $utime \
                                    $Mpri \
                                    $iscompleted
        }
    }
}

proc callib::deactivateButton {parent} {
    variable calState
    disableEditMode
    place forget $parent.create_note_frame
    foreach w [winfo children $parent.note_frame] {
        if { [string first label $w] ne -1 } {destroy $w}
    }
    foreach w [winfo children $parent.complete_note_frame] {
        if { [string first label $w] ne -1 } {destroy $w}
    }
    grid configure $parent.note_frame -column 1
    grid configure $parent.complete_note_frame -column 1
    if { [catch {set ::callib_notes_needs_full_update}] || $::callib_notes_needs_full_update eq 0} {} {
        ${::settings::main_obj}::my fillCalendarWidgetFromScheduler
        set ::callib_notes_needs_full_update 0
    }
    $parent.create_note_frame.entry delete 0 end
}

proc callib::addNote {parent entry position} {
    variable calState
    set text [string trim [$entry get]]
    if { [string length $text] eq 0 } {return}

    set day [format "%.2i" [$parent.frame$position.main_label cget -text]]
    set month [format "%.2i" $calState($parent.month)]
    set utime [clock scan $calState($parent.year)$month$day]

    while { [dict exists $::scheduler_data $utime] } {incr utime}
    dict append ::scheduler_data $utime "0 {$text}"
    ${::settings::main_obj}::my fillCalendarWidgetFromScheduler
    activateButton $parent
}

################################################################################
######### COMPLETE NOTE
proc callib::completeNote {note_label_widget key} {
    set data [dict get $::scheduler_data $key]
    set inverted_complete [expr { ![lindex $data 0] }]
    dict set ::scheduler_data $key [lreplace $data 0 0 $inverted_complete]
    # if { $inverted_complete } \
    #     {$note_label_widget configure -fg $::settings::complete_note_fg -font $::settings::complete_note_font} \
    #     {$note_label_widget configure -fg $::settings::note_fg -font $::settings::note_font}
    # [winfo parent $note_label_widget] configure
    inplaceMoveNote $note_label_widget
    ${::settings::main_obj}::my fillCalendarWidgetFromScheduler False True
}

proc callib::inplaceMoveNote {note_label_widget} {
    variable calState
    set name [winfo name $note_label_widget]
    regexp {.+([0-9]+)} $note_label_widget _ Mpri
    set parent [winfo parent $note_label_widget]
    set root_parent [winfo parent [winfo parent $parent]]
    set parent_is [winfo name $parent]
    set position [join $calState($root_parent.clicked) {}]
    set note_frame $root_parent.frame$position.note_frame
    set complete_note_frame $root_parent.frame$position.complete_note_frame
    set new_parent [expr {$parent_is eq {note_frame} ? $complete_note_frame : $note_frame}]
    set key [dict get $::global_params::widgets_utime $name]
    foreach {iscompleted note} [dict get $::scheduler_data $key] {}
    set widgets [list "$parent.label_remove$Mpri" \
                "$parent.label_complete$Mpri" \
                "$parent.label_edit$Mpri" \
                "$parent.note$Mpri"]
    # forget and destroy!
    grid forget {*}$widgets; destroy {*}$widgets
    if {[winfo children $parent] eq {}} {$parent configure -height 0}

    snipp::makeNoteLabel $new_parent.note$Mpri $note $iscompleted $Mpri
    createWidgetsForOneNote $new_parent \
                            $key \
                            $Mpri \
                            $iscompleted
}
######### COMPLETE NOTE
################################################################################

################################################################################
######### EDIT NOTE
proc callib::editNote {note_frame Mpri key} {
    set edit_entry $note_frame.edit_entry$Mpri
    set note $note_frame.note$Mpri
    #edit mode already active, disable it
    if { [disableEditMode $edit_entry $note $Mpri] eq {founded_and_disabled} } {return}
    entry $edit_entry
    $edit_entry insert 0 [$note cget -text]
    grid forget $note
    grid $edit_entry -row $Mpri -column 4 -sticky w -pady 1 -padx 5
    focus $edit_entry
    bind $edit_entry <Return> "callib::editNoteCallBack $edit_entry $note $Mpri $key"
    bind $edit_entry <Escape> "callib::disableEditMode $edit_entry $note $Mpri"
    set ::global_params::edit_note_entrys [      \
        list                                     \
            $::global_params::edit_note_entrys   \
            [list $edit_entry $note $Mpri]       \
    ]
}

proc callib::disableEditMode {{edit_entry none} {note none} {Mpri none}} {
    #edit mode already active, disable it
    if { [winfo exists $edit_entry] } {
        grid forget $edit_entry
        destroy $edit_entry
        grid $note -row $Mpri -column 4 -sticky w -pady 1 -padx 3
        return founded_and_disabled
    }
    #edit mode is active but for other note?
    foreach n $::global_params::edit_note_entrys {
        foreach {entry note Mpri} $n {
            if {[winfo exists $entry]} {
                grid forget $entry; destroy $entry
                grid $note -row $Mpri -column 4 -sticky w -pady 1 -padx 3
            }
        }
    }
    set ::global_params::edit_note_entrys {}
    return cleared!
}

proc callib::editNoteCallBack {edit_entry note Mpri key} {
    set text [string trim [$edit_entry get]]
    $note configure -text $text
    grid forget $edit_entry; destroy $edit_entry
    grid $note -row $Mpri -column 4 -sticky w -pady 1 -padx 3
    dict set ::scheduler_data $key [lreplace [dict get $::scheduler_data $key] 1 1 $text]
}
######### EDIT NOTE END
################################################################################

proc callib::changeEntrySize {entry} {
    if { [string length [$entry get]] < $::settings::note_length} 
        {return}
        {
            $entry configure 
        }
}

proc callib::removeNote {note_frame Mpri key} {
    dict unset ::scheduler_data $key
    set widgets [list "$note_frame.label_remove$Mpri"   \
                      "$note_frame.label_complete$Mpri" \
                      "$note_frame.label_edit$Mpri"     \
                      "$note_frame.note$Mpri" ]
    grid forget {*}$widgets
    destroy {*}$widgets
    if {[winfo children $note_frame] eq {}} {$note_frame configure -height 0}
    #set ::callib_notes_needs_full_update 1
    ${::settings::main_obj}::my fillCalendarWidgetFromScheduler False True
}

proc callib::clearWidgetsForMonthChange {parent} {
    foreach dw [winfo children $parent] {
        foreach fw [winfo children $dw] {
            set last [lindex [split $fw .] end]
            if { $last eq {create_note_frame} } { place forget $fw }
            if { $last ne {note_frame} && $last ne {complete_note_frame} } {continue}
            #catch {deactivateButton $fw}
            foreach iw [winfo children $fw] { destroy $iw }
        }
    }
    set ::global_params::widgets_utime {}
}

# this procedure gets called whenever a day button is pressed #
proc callib::callback {parent col row} {
    variable calState

    # cleanup previously clicked
    set old_col [lindex $calState($parent.clicked) 0]
    set old_row [lindex $calState($parent.clicked) 1]

    if {$old_row ne {}} {
        set button_name $parent.frame$old_col$old_row.main_label
        $button_name configure -background $::settings::background
        deactivateButton $parent.frame$old_col$old_row
        if {$old_row eq $row && $old_col eq $col} {
            set calState($parent.clicked) {}; return
        }
    };# END: there was a clicked button

    set calState($parent.clicked) [list $col $row]
    set button_name $parent.frame$col$row.main_label
    $button_name configure -background $::settings::clickedcolor
    # get the daynames from the state array
    set namelist $calState($parent.daynames)
    # if start on monday roll the list 
    if {$calState($parent.startsunday) != 1} {
        set namelist [roll_left $namelist]
    }
    activateButton $parent
    # make the arguments for the user defined callback procedure  
    set callargs [list $calState($parent.year)                         \
                       $calState($parent.month)                        \
                       [string trimleft [$parent.frame$col$row.main_label cget -text]] \
                       [lrange $namelist $col $col]                    \
                       $col                                            \
                       $row]
                       
    # procedure name                   
    set procname $calState($parent.callback)
    # if there is something registered as callback, call it
    if {$procname ne {}} {
        $procname {*}$callargs
    }
}

# this proc updates the calendar shown according to the contents #
# of the calState array                                          #
proc callib::update_cal parent {
    variable calState

    # set the frame color to the background
    $parent.fr configure -background $::settings::background
    # make the weekday list
    set weekdays $calState($parent.daynames)
    if {$calState($parent.startsunday) != 1} {
        set weekdays [roll_left $weekdays]
    };# END if not start on sunday -> start on monday 
    # update labels for the days header
    set colcount 0
    foreach day $weekdays {
        set daylabel $parent.$colcount
        #set day [string range $day 0 1]
        $daylabel configure -text $day -width 11                       \
                            -font $calState($parent.dayfont)          \
                            -foreground $calState($parent.daylabel_foreground) \
                            -background $::settings::background
        incr colcount
    };#END: foreach day in weekday 

    # get monthlist according to startsunday variable
    set month $calState($parent.month)
    set year  $calState($parent.year)
    set monthlist [cal_list_month $month \
                                  $year  \
                                  $calState($parent.startsunday)]
    # make an array with the day as index and the buttons coords as value
    # will be used while processing the marked days
    # first delete the array
    catch {unset index_arr}
    # fill buttons with the stuff
    for {set row 0} {$row < 6} {incr row} {
        for {set col 0} {$col < 7} {incr col} {
            set text [lindex $monthlist [expr {7*$row+$col}] ]
            set index_arr($text) $col$row
            # set default values, change them if day field is empty
            set reliefval $calState($parent.relief)
            set stateval  normal
            bind $parent.frame$col$row.main_label <Any-Enter> [list callib::enter_proc %W]
            bind $parent.frame$col$row.main_label <Any-Leave> [list callib::leave_proc %W]
            bind $parent.frame$col$row.main_label <Button-1>  [list callib::callback \
                                                     $parent         \
                                                     $col            \
                                                     $row]
            if {$text eq {}} {
                set reliefval flat
                set stateval  disabled
                bind $parent.frame$col$row.main_label <Any-Enter> {}
                bind $parent.frame$col$row.main_label <Any-Leave> {}
                bind $parent.frame$col$row.main_label <Button-1>  {}
            };# END: if dayfield is empty
            # reconfigure the button 
            $parent.frame$col$row.main_label configure -relief $reliefval -state $stateval \
                                       -borderwidth 2                      \
                                       -width 2                            \
                                       -bg $::settings::background         \
                                       -highlightbackground                \
                                         $::settings::background           \
                                       -font {Helvetica 16 bold }          \
                                       -text [format "%2s" $text]          \
                                       -justify center                     \
                                       -foreground                         \
                                         $calState($parent.foreground)

            $parent.frame$col$row.note_frame configure -bd 2               \
                                       -bg $::settings::background         \
                                       -highlightbackground                \
                                         $::settings::background

            $parent.frame$col$row.complete_note_frame configure -bd 2      \
                                       -bg $::settings::background         \
                                       -highlightbackground                \
                                         $::settings::background
        };#END: col
    };#END: row
    # check if there is a clicked day & update the color according to 
    # calstate array
    set col [lindex $calState($parent.clicked) 0]
    set row [lindex $calState($parent.clicked) 1]
    if {($row ne {}) && ($col ne {})} {
        $parent.frame$col$row.main_label configure -background $::settings::clickedcolor
    }
    # check if there are days in the marked list that are displayed
    # right now and mark them
    # put the needed part of mark list into the shownmarks list
    set calState($parent.shownmarks) {}
    foreach Mlist $calState($parent.mark) {
        foreach {Mday Mmonth Myear Mpri Mcol Mlabel} $Mlist {}
        if {$Myear == $calState($parent.year)} {
            if {$Mmonth == $calState($parent.month)} {
                lappend calState($parent.shownmarks) $Mlist
            }
        }
    }
    set calState($parent.shownmarks) [
        lsort -index 3 -integer $calState($parent.shownmarks)] 

    foreach Mlist $calState($parent.shownmarks) {
        # month & year are matching the shown ones, get the day
        foreach {Mday Mmonth Myear Mpri Mcol Mlabel} $Mlist {}
        $parent.frame$index_arr($Mday).main_label configure -highlightbackground $Mcol

        foreach {utime iscompleted note} $Mlabel {}
        # foreach {iscompleted note} [dict get $::scheduler_data $utime] {}
        set active_frame [expr {$iscompleted ? {complete_note_frame} : {note_frame}}]
        set note_label_widget $parent.frame$index_arr($Mday).$active_frame.note$Mpri

        # if { [string length $note] > $::settings::note_length } {
        #     set note [string range $note 0 $::settings::note_length]...
        # }
        snipp::makeNoteLabel $note_label_widget $note $iscompleted $Mpri $utime
    }
    catch {unset index_arr}
    return 
};# END update_cal

# gets called at each enter event #
proc callib::enter_proc wname {
    return
    variable calState

    # get parents name
    set parent [winfo parent [winfo parent $wname]]
    # set active color
    $wname configure -background $calState($parent.activebackground)
    #$wname configure -background $calState(.frame.calendar.activebackground)
    # trigger the balloon
    after $calState($parent.delay) [list callib::balloon_show $wname] 
}

# gets called at each leave event #
proc callib::leave_proc wname {
    variable calState

    # get parents name
    set parent [winfo parent [winfo parent $wname]]
    # set inactive color
    $wname configure -background $::settings::background
    # check if the label was "clicked" and set the color to clickedcolor
    set col [lindex $calState($parent.clicked) 0]  
    set row [lindex $calState($parent.clicked) 1]  
    if {$row ne {}} {
        set label_name $parent.frame$col$row.main_label
        $label_name configure -background $::settings::clickedcolor
    };# END: there was a clicked button
    # close the balloon
    balloon_dn $wname 
}

# triggers a balloon help like window #
proc callib::balloon_show wname {
    variable calState

    # get parents name
    set parent [winfo parent [winfo parent $wname]]
    # in case the balloons  are disabled do nothing
    if {$calState($parent.balloon) == 0} return
    # in case we already left the widget do nothing
    set currentwin [eval winfo containing [winfo pointerxy .]]
    if {![string match $currentwin $wname]} return
    # make a string with the marks of the date shown by the requester
    set day [string trim [$wname cget -text]]
    set message_str {} 
    foreach Mlist $calState($parent.shownmarks) {
        foreach {Mday Mmonth Myear Mpri Mcol Mlabel} $Mlist {}
            if {($Mday == $day)} {append message_str "$Mpri $Mlabel\n"}
    }
    set message_str [string trim $message_str]
    # if there are no marks for requesters widget return
    if {![string length $message_str]} return
    # create a top level window
    set top $parent.balloon
    catch {destroy $top}
    toplevel $top -borderwidth 1 -background black -relief flat
    wm overrideredirect $top 1
    # create the message widget
    message $top.msg -text $message_str  -width 3i\
                     -font $calState($parent.font)\
                     -background yellow -foreground darkblue
    pack $top.msg
    # get the geometry data of the requester
    set wmx [expr [winfo rootx $wname]+[winfo width  $wname]]
    set wmy [expr [winfo rooty $wname]+[winfo height $wname]]
    wm geometry $top [
        winfo reqwidth $top.msg]x[winfo reqheight $top.msg]+$wmx+$wmy
    # raise so that win is really on top
    raise $top
};# end balloon_show 

# makes the balloon disappear #
proc callib::balloon_dn wname {
    variable calState

    # get parents name
    set parent [winfo parent [winfo parent $wname]]
    # in case the balloons  are disabled do nothing
    if {$calState($parent.balloon) == 0} return
    # destroy the help balloon
    catch {destroy $parent.balloon}
};# end balloon_dn

# This proc takes care of all the configuration subcommands of #
# the calendar widget                                          #
proc callib::calproc {parent args} {
    variable calState

    # make a list of allowed commands
    # new commands should be dropped here & processed in the switch 
    # statement along with the possible subcommands
    set commList {nextmonth prevmonth nextyear prevyear configure clearMarks clearWidgets}
    # extract the first word in args, this must be in the commList
    set command [lindex $args 0]
    if {[lsearch -exact $commList $command] == -1} {
        error "unknown command for $parent, possible command(s):\n\
               $commList"
    };# END: check whether command is known to widget

    # remove the parent name from the args list
    set  args [lreplace $args 0 0]

    switch -- $command {
        configure {
            # if there are no arguments to configure
            # then return a list with all the configuration
            if {$args eq {}} {
                set optlist [array get calState $parent.*]
                set returnlist {} 
                foreach {opt val} $optlist {
                    regsub $parent. $opt {} opt
                    # shownmarks is a private field, so leave it out
                    if {$opt ne {shownmarks}} {
                        lappend returnlist [list $opt $val]
                      }
                }
                return $returnlist
            };# END: if no args for configure
            foreach {opt val} $args {
                switch -- $opt {
                    -font {
                        if {$val eq {}} {
                            return $calState($parent.font)
                        };# END: if no font specified
                        # might want to check whether font is available  
                        set calState($parent.font) $val
                    }
                    -background {
                        if {$val eq {}} {
                            return $::settings::background
                        };# END: if no color specified
                        set er [catch {label .tmp -background $val} result]
                        destroy .tmp   
                        if {$er} {
                            error "Problem with the color value\n\
                                  color is \"$val\""
                        }
                        set calState($parent.background) $val
                    }
                    -foreground {
                        if {$val eq {}} {
                            return $calState($parent.foreground)
                        };# END: if no color specified
                        set er [catch {label .tmp -foreground $val} result]
                        destroy .tmp   
                        if {$er} {
                            error "Problem with the color value\n\
                                  color is \"$val\""
                        }
                        set calState($parent.foreground) $val
                    }
                    -daylabel_foreground {
                        if {$val eq {}} {
                            return $calState($parent.daylabel_foreground)
                        };# END: if no color specified
                        set er [catch {label .tmp -foreground $val} result]
                        destroy .tmp
                        if {$er} {
                            error "Problem with the color value\n\
                                  color is \"$val\""
                        }
                        set calState($parent.daylabel_foreground) $val
                    }
                    -activebackground {
                        if {$val eq {}} {
                            return $calState($parent.activebackground)
                        };# END: if no color specified
                        set er [catch {label .tmp -background $val} result]
                        destroy .tmp   
                        if {$er} {
                            error "Problem with the color value\n\
                                  color is \"$val\""
                        }
                        set calState($parent.activebackground) $val
                    }
                    -dayfont {
                        if {$val eq {}} {
                            return $calState($parent.dayfont)
                        };# END: if no dayfont specified
                        set calState($parent.dayfont) $val
                    }
                    -clickedcolor {
                        if {$val eq {}} {
                            return $::settings::clickedcolor
                        };# END: if no clicked color specified
                        set er [catch {label .tmp -background $val} result]
                        destroy .tmp   
                        if {$er} {
                            error "Problem with the color value\n\
                                  color is \"$val\""
                        }
                        set calState($parent.clickedcolor) $val
                    }
                    -relief {
                        if {$val eq {}} {
                            return $calState($parent.relief)
                        };# END: if no relief specified
                        set er [catch {label .tmp -relief $val} result]
                        destroy .tmp   
                        if {$er} {
                            error "Problem with the relief value\n\
                                  relief is \"$val\""
                        }
                        set calState($parent.relief) $val
                    }
                    -startsunday {
                        if {$val eq {}} {
                            return $calState($parent.startsunday)
                        };# END:  if no value for start sunday
                        set calState($parent.startsunday) 0  
                        if {$val == 1} {
                            set calState($parent.startsunday) 1
                        } 
                        # get rid of clicked state as calendar is going
                        # to change layout
                        set calState($parent.clicked) {}  
                    }
                    -balloon {
                        if {$val eq {}} {
                            return $calState($parent.balloon)
                        };# END:  if no value for balloon
                        set calState($parent.balloon) 0  
                        if {$val == 1} {
                            set calState($parent.balloon) 1
                        } 
                    }
                    -delay {
                        if {$val eq {}} {
                            return $calState($parent.delay)
                        };# END:  if no value for balloon delay
                        # delay check: must be integer
                        set er [catch {incr val 0}]
                        if {$er} {
                            error "Problem with the delay value\n\
                                  most likely a non integer value \n\
                                  given delay is \"$val\""
                        }
                        if {$val < 0} {
                            error "Problem with negative delay value\n\
                                  given delay is \"$val\""
                        }
                        set calState($parent.delay) $val 
                    }
                    -progcallback {
                        if {$val eq {}} {
                            return $calState($parent.progcallback)
                        };# END:  if no value for progcallback
                        set calState($parent.progcallback) 0  
                        if {$val == 1} {
                            set calState($parent.progcallback) 1
                        } 
                    }
                    -mark {
                        if {$val eq {}} {
                            return $calState($parent.mark)
                        };# END: if no marking list given
                        if {[llength $val] != 6} {
                            error "The mark list must have 6 elements\n\
                                   a mark list should be like this:  \n\
                                   {day month year prio color label}"
                        };# END: if mark list not properly constructed
                        
                        # assign temp_vars  
                        foreach {Mday Mmonth Myear Mpri Mcol Mlabel} $val {}
                        
                        # check the list fields for consistency  
                        # check the month
                        if {($Mmonth < 1) || ($Mmonth > 12)} {
                            error {Month out of range}
                        }
                        # check year and month, compute the number of days
                        # of the given month
                        set er [catch {cal_month_length $Mmonth $Myear} Ml]
                        if {$er} {
                            error "Problem computing month length,\n\
                                  year out of clock's range or erroneous\n\
                                  month value"
                        }
                        # day check
                        if {($Mday < 1) || ($Mday > $Ml)} {
                            error "Day of month out of range"
                            return
                        }
                        # prio check: must be integer
                        set er [catch {incr Mpri 0}]
                        if {$er} {
                            error "Problem with the priority value\n\
                                  most likely a non integer value \n\
                                  prio is \"$Mpri\""
                        }
                        # check that color is acceptable
                        set er [catch {label .tmp -background $Mcol} result]
                        destroy .tmp   
                        if {$er} {
                            error "Problem with the color value\n\
                                  color is \"$Mcol\""
                        }
                        # all consistency checks went OK
                        # append mark to mark list
                        lappend calState($parent.mark) $val
                    }
                    -daynames {
                        if {$val eq {}} {
                            return $calState($parent.daynames)
                        };# END: if no list with daynames specified
                        if {[llength $val] != 7} {
                            error "The list given to -daynames must have\n\
                                   7  elements, [llength $val] elements \n\
                                   were specified in $val"
                        };# END: if list didn't have 7 elements
                        set calState($parent.daynames) $val  
                    }
                    -clicked {
                        if {$val eq {}} {
                            return $calState($parent.clicked)
                        };# END: if no list with  calendar coordinates 
                        if {[llength $val] != 2} {
                            error "The list given to -clicked must have\n\
                                   2  elements, [llength $val] elements \n\
                                   were specified in $val"
                        };# END: if list didn't have 2 elements
                        set tmp_col [lindex $val 0]
                        set tmp_row [lindex $val 1]
                        if {($tmp_col < 0) || ($tmp_col > 6)} {
                            error "column value for clicked cell invalid\n\
                                   0<= col < 7 allowed, given: $tmp_col"
                        };# END: if coord isn't in right range
                        if { ($tmp_row < 0) || ($tmp_row > 5)} {
                            error "row value for clicked cell invalid\n\
                                   0<= col < 5 allowed, given: $tmp_col"
                        };# END: if coord isn't in right range
                        set Cstate [$parent.$tmp_col$tmp_row cget -state]
                        if {$Cstate eq {normal}} {              
                            set calState($parent.clicked) $val  
                            # call the callback as if the appropriate button
                            # was clicked. 
                            if {$calState($parent.progcallback)=="1"} {
                                callback $parent $tmp_col $tmp_row   
                              };# end: if programm callback enabled  
                        };# END: if cell is not disabled
                    }    
                    -month {
                        if {$val eq {}} {
                            return $calState($parent.month)
                        };# END: if no month specified
                        if {($val > 0) && ($val < 13)} {
                            set calState($parent.month) $val
                        } else {
                            error {Month value must be between 1 and 12}
                        }
                        set calState($parent.clicked) {}  
                      }
                    -year {
                        if {$val eq {}} {
                            return $calState($parent.year)
                        };# END: if no year specified
                        set calState($parent.year) $val
                        set calState($parent.clicked) {}
                    }     
                    -callback {
                        if {$val eq {}} {
                            return $calState($parent.callback)
                        };# END: if no year specified
                        set calState($parent.callback) $val
                    }
                    default {
                        error "Bad option: $opt\n\
                               allowed option(s) for configure are:    \n\
                               -font -startsunday -daynames -month     \n\
                               -year -dayfont -callback -clickedcolor  \n\
                               -background -clicked -mark -balloon     \n\
                               -progcallback -activebackground -delay  \n\
                               -foreground -self" 
                    }
                }
            }
            update_cal $parent  
        }
        nextmonth {
            if {[llength $args]} {
                error "nextmonth not allowed to have arguments"
            };# END: check number of arguments error if != 0
            incr calState($parent.month)
            if {$calState($parent.month) == 13} {
                set calState($parent.month) 1
                incr calState($parent.year)
            };# END: if month crossed year boundary to next year
            set calState($parent.clicked) {}
            clearWidgetsForMonthChange $parent
            update_cal $parent
            return [list $calState($parent.year) $calState($parent.month)]
        }
        prevmonth {
            if {[llength $args]} {
                error {prevmonth not allowed to have arguments}
            };# END: check number of arguments error if != 0
            incr calState($parent.month) -1
            if {$calState($parent.month) == 0} {
                set calState($parent.month) 12
                incr calState($parent.year) -1
            };# END: if month crossed year boundary to previous year
            set calState($parent.clicked) {}
            clearWidgetsForMonthChange $parent
            update_cal $parent  
            return [list $calState($parent.year) $calState($parent.month)]
        }
        nextyear {
            if {[llength $args]} {
                error "nextyear not allowed to have arguments"
            };# END: check number of arguments error if != 0
            incr calState($parent.year)
            set calState($parent.clicked) {}
            clearWidgetsForMonthChange $parent
            update_cal $parent  
            return [list $calState($parent.year) $calState($parent.month)]
        }
        prevyear {
            if {[llength $args]} {
                error {prevyear not allowed to have arguments}
            };# END: check number of arguments error if != 0
            incr calState($parent.year) -1
            set calState($parent.clicked) {}
            clearWidgetsForMonthChange $parent
            update_cal $parent  
            return [list $calState($parent.year) $calState($parent.month)]
        }
        clearMarks {
            set calState($parent.mark) {}
            set calState($parent.shownmarks) {}
        }
        clearWidgets {
            clearWidgetsForMonthChange $args
        }
        default {
            error "You should never have reached this point\n\
                   The state of the widget might be mangled\n\
                   Bailing out, bye\n"
        }
    };# END: switch -- $command
};# END: calproc
  
#utilities start here
#anything needing calState does not belong below

# helper function to roll a list to the left #
proc callib::roll_left {listvar {rollby 1}} {
    set newlist $listvar
    for {set counter 0} {$counter < $rollby} {incr counter} {
        set firstelem [lindex $newlist 0]
        set newlist   [lreplace $newlist 0 0]
        set newlist   [lappend newlist $firstelem]
    }
    return $newlist
};# END roll_left
  
# returns the weekday as an ordinal number #
# sunday is 0                              #
proc callib::cal_start_weekday {month year} {
    # obvious, needed as a wrapper for future 
    # sophistication of the proc
    set startday [clock scan $month/1/$year]
    return [clock format $startday -format %w]
};# END: cal_start_weekday
  
# returns the length of a month #
proc callib::cal_month_length {monthvar yearvar} {
    # get clock ticks
    # make sure to stay in same month to stay in same year
    set startdate    [clock scan $monthvar/1/$yearvar]
    set enddate      [clock scan "+1 month" -base $startdate]
    set lastmonthday [clock scan "yesterday"  -base $enddate]

    # get day numbers from ticks
    set lastday      [clock format $lastmonthday -format %d]

    # get rid of leading zeroes as tcl interpret them as octal
    set lastday  [string trimleft $lastday 0]

    # actually not needed (clock ... %d returns min. 01)
    # but keep sane state for the variables
    if {$lastday eq {}} {set lastday 0}
    return $lastday 
};# END: cal_month_length
  
# returns a list of 35 elements containing the month #
# start day of week is sunday by default             #
proc callib::cal_build_month { month year } {
    set startday [cal_start_weekday $month $year]
    set numdays  [cal_month_length  $month $year]

    # put month there
    for {set counter 1} {$counter <= $numdays} {incr counter} {
        set monthlist [lappend monthlist $counter]
    }
    # make empty preceeding days if needed
    if {$startday != 0} {
        for {set counter 0} {$counter < $startday} {incr counter} {
            set prelist [lappend prelist {}]
        }
        return [concat $prelist $monthlist]
    }
    return $monthlist
};# END: cal_build_month
  
# return the monthlist with start either mondays or sundays #
proc callib::cal_list_month {month year {startsunday 1}} {
    # get the default (start sunday) list
    set monthlist [cal_build_month $month $year ]

    if {$startsunday != 1} {
        # start week as in Europe
        set firstday [cal_start_weekday $month $year]
        if {$firstday == 0} {
            set monthlist [linsert $monthlist 0 {} {} {} {} {} {}]
        } else {
            set monthlist [roll_left $monthlist]
        }
    }
    return $monthlist
};# END: cal_list_month