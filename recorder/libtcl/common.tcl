package require Tcl 8.5
package require log 1.3
package require cmdline 1.3.3

set ::configDir [file normalize ~/.config/talkrec]
set ::dryRun 0

proc getOptions {optionsDesc {usage "options"}} {
    set optDesc $optionsDesc
    lappend optDesc {dry-run "Не выполнять команды, меняющие ситуацию, а только показывать их"}
    lappend optDesc {debug "Показывать отладочный вывод"}
    array set ::opt [::cmdline::getoptions ::argv $optDesc $usage]
    ::log::lvSuppressLE emergency 0
    if {!$::opt(debug)} {::log::lvSuppress debug}
    if {$::opt(dry-run)} {set ::dryRun 1}
}

proc fileModified {file} {
    set mtime [file mtime $file]
    if {![info exists ::mtime($file)] || $mtime > $::mtime($file)} {
	set ::mtime($file) $mtime
	return true
    } else {
	return false
    }
}

proc listOfErrors {context errors} {
    set res $context
    append res ":"
    foreach err $errors {append res "\n- " $err}
    return $res
}

proc run {args} {
    if {$::dryRun} {
	::log::log info [concat {Would run:} $args]
	return dryRun
    } else {
	::log::log debug $args
	{*}$args
    }
}

proc createFileViaTmp {filename chanvar script} {
    upvar $chanvar chan
    set tmpname $filename.tmp
    run file delete -- $tmpname
    set chan [run open $tmpname w]
    try {
	uplevel $script
    } finally {
	run close $chan
    }
    run file rename -- $tmpname $filename
}

proc debugStackTrace {statusDict} {
    catch {dict get $statusDict -errorinfo} stackTrace
    ::log::log debug $stackTrace
}

proc checkDict {dict checks} {
    set errors {}
    foreach check $checks {
	set key [lindex $check 0]
	if {$key eq ""} continue
	set meaning [lindex $check 1]
	if {$meaning eq ""} {
	    set what $key
	} else {
	    set what "$meaning ($key)"
	}
	if {![dict exists $dict $key]} {
	    lappend errors "$what отсутствует"
	    continue
	}
	set value [dict get $dict $key]
	switch [llength $check] {
	    3 {
		set re [lindex $check 2]
		if {![regexp $re $value]} {lappend errors "$what: недопустимое значение $value"}
	    }
	}
    }
    return $errors
}
