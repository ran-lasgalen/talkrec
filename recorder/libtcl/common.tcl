package require Tcl 8.5
package require log 1.3
package require cmdline 1.3.3
package require yaml 0.3.6

set ::configDir [file normalize ~/.config/talkrec]
set ::dryRun 0

proc configFile {filename} {
    file normalize [file join $::configDir $filename]
}

proc getOptions {defaultConfig optionsDesc {usage "options"}} {
    try {
	array set ::opt {}
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
    } on error {err dbg} {
	debugStackTrace $dbg
	puts stderr $err
	exit 1
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

proc run! {args} {
    if {$::dryRun} {set lvl info} {set lvl debug}
    ::log::log $lvl $args
    {*}$args
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
	1 {set script [lindex $args 0]}
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

proc safelog {logdata} {
    if {[catch {uplevel 1 [concat ::log::log $logdata]} err dbg]} {
	debugStackTrace $dbg
    }
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

proc wavDuration {file} {
    proc parseFmtChunk {chan scanFmts} {
	array set scanFmt $scanFmts
	binary scan [read $chan 16] $scanFmt(fmt) \
	    fmt channels freq bytesPerSec bytesPerSample bitsPerSample
	set res [list fmt $fmt channels $channels bytesPerSec $bytesPerSec bytesPerSample $bytesPerSample bitsPerSample $bitsPerSample]
	if {$fmt != 1} {	# extra header
	    binary scan [read $chan 2] $scanFmt(16) extra
	    lappend res extra $extra
	}
	return $res
    }
    set wav [open $file r]
    fconfigure $wav -translation binary
    set magic [read $wav 4]
    switch $magic {
	RIFF {set scanFmts {16 s 32 i fmt "ssiiss"}}
	RIFX {set scanFmts {16 S 32 I fmt "SSIISS"}}
	default {error "Bad magic '$magic'"}
    }
    array set scanFmt $scanFmts
    # len should be file length - 8, but we just ignore it
    binary scan [read $wav 4] $scanFmt(32) len
    set type [read $wav 4]
    if {$type ne "WAVE"} {error "Not a WAVE file: '$type'"}
    set dataLen 0
    set format {}
    while {1} {
	set chunkType [read $wav 4]
	if {[eof $wav]} break
	binary scan [read $wav 4] $scanFmt(32) len; # chunk length
	set eoc [expr {[tell $wav] + $len}];	    # end of chunk
	switch [string tolower [string trim $chunkType]] {
	    fmt {set format [parseFmtChunk $wav $scanFmts]}
	    data {incr dataLen $len}
	}
	seek $wav $eoc start
    }
    array set fmt $format
    if {![info exists fmt(bytesPerSec)]} {
	error "No format chunk or bytesPerSec data in it"
    }
    expr {double($dataLen) / $fmt(bytesPerSec)}
}
