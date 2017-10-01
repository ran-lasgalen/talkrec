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

proc runProcInLoop {args} {
    set cmd [concat | $args 2>@1]
    ::log::log notice "Running: $args"
    if {[catch {open $cmd r} pipe]} {
	::log::log error "Не удалось запустить $args:\n"
	return
    }
    fconfigure $pipe -blocking 0
    fileevent $pipe readable [list waitProc $pipe $args]
}

proc waitProc {pipe cmd} {
    set data [read $pipe]
    if {$data ne ""} {puts -nonewline $data; flush stdout}
    if {[eof $pipe]} {
	if {[catch {close $pipe} err]} {
	    ::log::log error "$cmd:\n  $err\nrestart after 12 sec"
	} else {
	    ::log::log notice "$cmd finished\nrestart after 12 sec"
	}
	after 12000 [concat runProcInLoop $cmd]
    }
}
