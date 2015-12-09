namespace eval snippets {
    namespace export select listc com lambda

    # RS, modified by Duoas http://wiki.tcl.tk/3146
    #
    proc select {varNames from list where condition} {
        foreach varName $varNames {
            upvar 1 $varName $varName
        }
        set result {}
        foreach $varNames $list {
            if {[uplevel 1 expr $condition]} {
                set ls [list]
                foreach varName $varNames {
                    lappend ls [set $varName]
                }
                lappend result $ls
            }
        }
        return $result
    }

    # http://wiki.tcl.tk/3146
    # Synopsis:
    # listc expression vars1 <- list1 [.. varsN <- listN] [condition].
    #
    proc listc {expression var1 <- list1 args} {
        set res {}
      
        # Conditional expression (if not supplied) is always 'true'.
        set condition {expr 1}
      
        # We should at least have one var/list pair.
        lappend var_list_pairs  $var1 $list1
      
        # Collect any additional var/list pairs.
        while {[llength $args] >= 3 && [lindex $args 1] == "<-"} {
            lappend var_list_pairs [lindex $args 0]
            # skip "<-"
            lappend var_list_pairs [lindex $args 2]
            set args [lrange $args 3 end]
        }
     
      
        # Build the foreach commands (for each var/list pair).
        foreach {var list} $var_list_pairs {
            append foreachs [string map [list \${var} [list $var] \${list} \
                [list $list]] "foreach \${var} \${list} \{
                "]
        }

        # Remaining args are conditions
        # Insert the conditional expression.
        append foreachs [string map [list \${conditions} [list $args] \
            \${expression} [list $expression]] {

            set discard 0
            foreach condition ${conditions} {
                if !($condition) {
                    set discard 1
                    break
                }
            }
            if {!$discard} {
                lappend res [expr ${expression}]
            }
        }]

        
        # For each foreach, make sure we terminate it with a closing brace.
        foreach {var list} $var_list_pairs {
            append foreachs \}
        }
      
        # Evaluate the foreachs...
        eval $foreachs
        return $res
    } 

    # http://wiki.tcl.tk/3146
    # Another variant, from CMcC 2010-07-01 10:14:25, modified by pyk 2013-08-04:
    # Unlike the main script on this page, this variant iterates over the lists simultaneously, in the manner of [foreach] rather than treating them as nested [foreach] commands.
    # Each list is given a positional variable $0...$n in the expression
    #
    proc com {expr args} {
        ::set vars {}
        ::set foreachs {}
        ::set i -1
        while {[llength $args] >= 3 && [lindex $args 1] == {<-}} {
            dict set foreachs [lindex $args 0] [lindex $args 2]
            lappend vars "\[set [list [lindex $args 0]]]"
            set args [lrange $args 3 end]
        }

        foreach {*}$foreachs {
            ::set vals [subst $vars]
            set keep 1 
            foreach condition $args {
                if {![uplevel 1 [list ::apply [list [dict keys $foreachs] \
                    [list expr $condition]] {*}$vals]]} {
                    set keep 0
                    break
                }
            }
            if {$keep} {
                lappend result [::uplevel 1 [list ::apply [list [dict keys $foreachs] [list expr $expr]] {*}$vals]]
            }
        }
        
        return $result
    }

    proc lambda {arglist body {ns {}}} {
     list ::apply [list $arglist $body $ns]
   }
}
