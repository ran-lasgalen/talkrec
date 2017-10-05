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
	run exec sudo apt-get install {*}$need >@ stdout 2>@ stderr
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

proc filesEqual {f1 f2} {
    if {![file exists $f1] && ![file exists $f2]} {return 1}
    if {![file exists $f1] || ![file exists $f2]} {return 0}
    expr {[::md5::md5 -hex -file $f1] eq [::md5::md5 -hex -file $f2]}
}

proc installSystemdService {exampleFile {service ""}} {
    set serviceDir [file normalize ~/.config/systemd/user]
    run file mkdir $serviceDir
    set content [fixExamplePathsIn [readFile $exampleFile]]
    if {$service eq ""} {
	set service [file tail $exampleFile]
    }
    if {![regsub {\.service\M.*} $service .service service]} {
	append service .service
    }
    set serviceFile [file join $serviceDir $service]
    set tmpFile $serviceFile.tmp
    run file delete -- $tmpFile
    set fh [run open $tmpFile w]
    run puts -nonewline $fh $content
    run close $fh
    if {[catch {readFile [list | loginctl show-user $::tcl_platform(user)]} showUser]} {
	set lingerEnabled 0
    } else {
	set lingerEnabled [regexp Linger=yes $showUser]
    }
    if {!$lingerEnabled} {runExec loginctl enable-linger $::tcl_platform(user)}
    if {[filesEqual $tmpFile $serviceFile]} {
	run file delete -- $tmpFile
    } else {
	run file rename --force $tmpFile $serviceFile
	runExec systemctl --user daemon-reload
    }
    runExec systemctl --user enable $service
    catch {runExec systemctl --user stop $service}
    runExec systemctl --user start $service
    runExec sleep 2
    runExec systemctl --user status $service
}
