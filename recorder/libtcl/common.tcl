package require Tcl 8.5
package require log 1.3
package require cmdline 1.3.3

set ::configDir [file normalize ~/.config/talkrec]
set ::dryRun 0

proc configFile {filename} {
    file normalize [file join $::configDir $filename]
}

proc getOptions {defaultConfig optionsDesc {usage "options"}} {
    set optDesc $optionsDesc
    set okIfNoDefaultConfig 0
    if {[regexp {^-(.*)} $defaultConfig - defaultConfig]} {set okIfNoDefaultConfig 1}
    lappend optDesc [list config.arg $defaultConfig "Файл конфигурации"]
    lappend optDesc {dry-run "Не выполнять команды, меняющие ситуацию, а только показывать их"}
    lappend optDesc {debug "Показывать отладочный вывод"}
    array set ::opt [::cmdline::getoptions ::argv $optDesc $usage]
    ::log::lvSuppressLE emergency 0
    if {!$::opt(debug)} {::log::lvSuppress debug}
    if {$::opt(dry-run)} {set ::dryRun 1}
    if {![file exists $::opt(config)]} {
	if {$::opt(config) ne $defaultConfig || !$okIfNoDefaultConfig} {
	    error "Не найден файл конфигурации $::opt(config)"
	}
    } elseif {![file readable $::opt(config)]} {
	error "Недостаточно прав для чтения файла конфигурации $::opt(config)"
    }
    if {[file pathtype $::opt(config)] ne "absolute"} {
	set ::opt(config) [file normalize $::opt(config)]
    }
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
    if {$context eq ""} {
	set res {}
    } else {
	set res [list [string cat $context :]]
    }
    foreach err $errors {lappend res [string cat "  - " $err]}
    join $res "\n"
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

proc runExec {args} {run exec {*}$args >@ stdout 2>@ stderr}

proc findExecutable {bin} {
    set PATH [split $::env(PATH) :]
    foreach bindir {/usr/local/bin /usr/local/sbin /bin /usr/bin /sbin /usr/sbin} {
	if {[lsearch -exact $PATH $bindir] < 0} {lappend PATH $bindir}
    }
    foreach bindir $PATH {
	set fullbin [file join $bindir $bin]
	if {[file executable $fullbin]} {return $fullbin}
    }
    return {}
}

proc readFile {file} {
    set fh [run open $file r]
    set res [run read $fh]
    run close $fh
    return $res
}

proc createFileViaTmp {filename chanvarOrContent args} {
    switch [llength $args] {
	0 {return [createFileViaTmp $filename createFileViaTmpFH {run puts $createFileViaTmpFH $chanvarOrContent}]}
	1 {}
	default {
	    error "Wrong number of arguments: createFileViaTmp filename chanvarOrContent [script]"
	}
    }
    upvar $chanvarOrContent chan
    set tmpname $filename.tmp
    run file delete -- $tmpname
    set chan [run open $tmpname w]
    try {
	uplevel $script
    } finally {
	run close $chan
    }
    run file rename -force -- $tmpname $filename
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
