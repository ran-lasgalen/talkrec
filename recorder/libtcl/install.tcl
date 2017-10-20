proc debsYetToInstall {debs} {
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
    return $need
}

proc installDebs {debs} {
    set need [debsYetToInstall $debs]
    if {[llength $need] > 0} {
	prepareSudo
	runExec sudo apt-get install --yes {*}$need
    }
}

proc sudoWithPw {args} {
    if {"sudo" ni $args} {set args [concat {sudo -S} $args]}
    set cmd [concat | $args {>@ stdout 2>@ stderr}]
    safelog {debug $cmd}
    try {
	set pipe [open $cmd w]
	try { puts $pipe $::sudoPassword } finally { close $pipe }
    } on error err {
	error "sudoWithPw $args:\n  $err"
    }
}

proc lingerEnabled {} {
    try {
	regexp Linger=yes [readFile [list | loginctl show-user $::tcl_platform(user)]]
    } on error {err dbg} {
	debugStackTrace $dbg
	error "loginctl не работает, включить Linger не получится"
    }
}

proc readPassword {prompt} {
    try {
	catch {exec stty -echo}
	puts -nonewline "$prompt: "
	flush stdout
	gets stdin line
	puts ""
	string trim $line
    } finally {
	catch {exec stty echo}
    }
}

proc prepareSudo {{password {}}} {
    try {
	if {![catch {exec sudo -n true}]} {return 1}
	if {$password eq ""} {
	    if {[info exists ::sudoPassword]} {
		set password $::sudoPassword
	    } else {
		set password [readPassword "password for sudo"]
	    }
	}
	set pipe [open {| sudo -S true 2> /dev/null} w]
	puts $pipe $password
	close $pipe
	set ::sudoPassword $password
	return 1
    } on error err {
	error "prepareSudo failed: $err"
    }
}

proc prefixLines {prefix message} {
    string cat $prefix [join [split $message \n] "\n$prefix"]
}

proc execInLoop {id args} {
    set cmd [concat | $args 2>@1]
    puts [prefixLines "$id: " "запускаем: $args"]
    flush stdout
    if {[catch {open $cmd r} pipe]} {
	puts [prefixLines "$id: " "не удалось запустить $args:\n$pipe"]
	flush stdout
	return
    }
    fconfigure $pipe -blocking 0
    fileevent $pipe readable [list waitProc $pipe $id $args]
}

proc waitProc {pipe id cmd} {
    while {[gets $pipe line] >= 0} {
	puts "$id: $line"
    }
    if {[eof $pipe]} {
	if {[catch {close $pipe} err]} {
	    puts [prefixLines "$id: " "$cmd:\n  $err\nrestart after 12 sec"]
	} else {
	    puts [prefixLines "$id: " "$cmd finished\nrestart after 12 sec"]
	}
	after 12000 [concat execInLoop $id {*}$cmd]
    }
    flush stdout
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

proc inputDict {dictPrompt keyPrompt valuePrompt} {
    set res [dict create]
    puts $dictPrompt
    while {1} {
	puts -nonewline "Enter - завершить ввод, \\ - начать сначала\n$keyPrompt: "
	flush stdout
	set k [gets stdin]
	if {$k eq ""} {return $res}
	if {$k eq "\\"} {set res [dict create]; continue}
	set key [string trim $k]
	if {[dict exists $res $key]} {set dflt " \[[dict get $res $key]]"} else {set dflt {}}
	puts -nonewline "$valuePrompt$dflt: "
	flush stdout
	set value [string trim [gets stdin]]
	dict set res $key $value
	puts "Введено: [list $res]"
    }
}

proc inputList {listPrompt elementPrompt} {
    set res {}
    puts $listPrompt
    while {1} {
	puts -nonewline "Enter - завершить ввод, \\ - начать сначала\n$elementPrompt: "
	flush stdout
	set e [gets stdin]
	if {$e eq ""} {return $res}
	if {$e eq "\\"} {set res {}; continue}
	lappend res [string trim $e]
	puts "Введено: [list $res]"
    }
}
