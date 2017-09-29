proc installDebs {debs} {
    set need {}
    foreach deb $debs {
	set found 0
	try {
	    set pipe [open [list | dpkg -s $deb 2>/dev/null]]
	    while {[gets $pipe line] >= 0} {
		if {[regexp {^Status:.*installed} $line]} {set found 1}
	    }
	    close $pipe
	} on error {} {}
	if {!$found} {lappend need $deb}
    }
    if {[llength $need] > 0} {
	run exec sudo apt-get install {*}$need
    }
}
