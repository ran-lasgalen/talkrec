package require Tcl 8.5
package require log 1.3
package require yaml 0.3.6
package require json 1.3
package require json::write 1.0.2

set ::configDir [file normalize ~/.config/talkrec]
set ::dryRun 0

proc configFile {filename} {
    file normalize [file join $::configDir $filename]
}

proc configDictFile {filename} {dictFile [configFile $filename]}

proc usage {optionsDesc {message {}} {usage options}} {
    set msg {}
    if {$message ne ""} {lappend msg $message}
    lappend msg "Usage: [file tail $::argv0] $usage"
    foreach od $optionsDesc {
	if {[llength $od] == 2} {
	    lappend msg "  [lindex $od 0]\t[lindex $od 1]"
	} elseif {[llength $od] == 3} {
	    lappend msg "  [lindex $od 0]\t[lindex $od 2] \[[lindex $od 1]]"
	} else {
	    lappend msg "  $od"
	}
    }
    join $msg "\n"
}

proc parseOptions {argsVar optionsDesc {usage options}} {
    upvar $argsVar argv
    array set options {}
    set leftArgs {}
    proc mainOptKey {optDesc} {
	set o [lindex $optDesc 0 0]
	regexp {^-(-.*)} $o - o
	return $o
    }
    lappend optionsDesc {--debug "включить отладку"}
    lappend optionsDesc {--dry-run "Не выполнять команды, меняющие ситуацию, а только показывать их"}
    lappend optionsDesc {-- "дальше - не опции"}
    lappend optionsDesc {--help "список опций"}
    foreach opt $optionsDesc {
	if {[lindex $opt 0 0] in {-- --help}} continue
	set k [mainOptKey $opt]
	switch [llength $opt] {
	    2 {set options($k) 0}
	    3 {set options($k) [lindex $opt 1]}
	    default {error "Ошибка описания опции '$opt'.\nОписание опции - 2- или 3-элементный список"}
	}
    }
    while {[llength $argv] > 0} {
	set el [lindex $argv 0]
	set argv [lreplace $argv 0 0]
	set found 0
	foreach optDesc $optionsDesc {
	    if {$found} continue
	    foreach ov [lindex $optDesc 0] {
		if {$found} continue
		if {$ov eq $el} {
		    if {$ov eq "--"} {
			set argv [concat $leftArgs $argv] 
			return [array get options]
		    }
		    set found 1
		    set k [mainOptKey $optDesc]
		    switch [llength $optDesc] {
			2 {set options($k) 1}
			3 {
			    if {[llength $argv] == 0} {error [usage $optionsDesc "Опция $ov требует аргумента" $usage]}
			    set options($k) [lindex $argv 0]
			    set argv [lreplace $argv 0 0]
			}
		    }
		}
	    }
	}
	if {!$found} {
	    if {[regexp {^-.} $el]} {error [usage $optionsDesc "Неизвестная опция $el" $usage]}
	    lappend leftArgs $el
	}
    }
    set argv $leftArgs
    return [array get options]
}

proc getOptions {defaultConfig optionsDesc {usage "options"}} {
    try {
	array set ::opt {}
	set optDesc $optionsDesc
	set okIfNoDefaultConfig 0
	if {[regexp {^-(.*)} $defaultConfig - defaultConfig]} {set okIfNoDefaultConfig 1}
	lappend optDesc [list --config $defaultConfig "Файл конфигурации"]
	array set ::opt [parseOptions ::argv $optDesc $usage]
	::log::lvSuppressLE emergency 0
	if {!$::opt(-debug)} {::log::lvSuppress debug}
	if {$::opt(-dry-run)} {set ::dryRun 1}
	if {![file exists $::opt(-config)]} {
	    if {$::opt(-config) ne $defaultConfig || !$okIfNoDefaultConfig} {
		error "Не найден файл конфигурации $::opt(-config)"
	    }
	} elseif {![file readable $::opt(-config)]} {
	    error "Недостаточно прав для чтения файла конфигурации $::opt(-config)"
	}
	if {[file pathtype $::opt(-config)] ne "absolute"} {
	    set ::opt(-config) [file normalize $::opt(-config)]
	}
	set ::paths [dict create]
	catchDbg {set ::paths [readDict [configDictFile paths]]} 
    } on error {err dbg} {
	debugStackTrace $dbg
	puts stderr $err
	exit 1
    }
}

proc parseObject {text} {
    switch -regexp $text {
	"^\\s*\\\{" {::json::json2dict $text}
	"^\\s*\\\[" {::json::many-json2dict $text}
	default {::yaml::yaml2dict $text}
    }
}

proc dictFile {fileBase} {
    switch -glob $fileBase {
	*.json -
	*.yaml -
	*.yml {
	    if {[file exists $fileBase]} {
		return $fileBase
	    } else {
		error "$fileBase не существует"
	    }
	}
	default {
	    set exts {json yaml yml}
	    foreach ext $exts {
		if {[file exists $fileBase.$ext]} {return $fileBase.$ext}
	    }
	    error "$fileBase{.[join $exts ,.]} не существуют"
	}
    }
}

proc readDict {fileBase} {
    set file [dictFile $fileBase]
    safelog {debug "Reading $file"}
    switch -glob $file {
	*.json {::json::json2dict [readFile! $file]}
	*.yml -
	*.yaml {::yaml::yaml2dict -file $file}
	default {parseObject [readFile! $file]}
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
	safelog {info [concat {Would run:} $args]}
	return dryRun
    } else {
	safelog {debug $args}
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

proc readFile! {file} {
    set fh [open $file r]
    try { read $fh } finally { close $fh }
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
    catch {::log::log debug $stackTrace}
}

proc catchDbg {script} {
    if {[catch {uplevel 1 $script} err dbg]} {
	debugStackTrace $dbg
    }
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

proc splitAddr {addr defaultPort} {
    if {[regexp {^([\w.-]+):(\d+)$} $addr - host port]} {return [list $host $port]}
    if {[regexp {^\[([\d:]+)\]:(\d+)$} $addr - host port]} {return [list $host $port]}
    if {[regexp {^(\S+)\s+(\d+)$} $addr - host port]} {return [list $host $port]}
    return [list $addr $defaultPort]
}

proc formatTimeInterval {seconds} {
    if {$seconds < 0} {return "-[formatTimeInterval [expr {abs($seconds)}]]"}
    set h [expr {$seconds / 3600}]
    set m [expr {$seconds % 3600 / 60}]
    set s [expr {$seconds % 60}]
    if {$h > 0} {
	format "%d:%02d:%02d" $h $m $s
    } else {
	format "%d:%02d" $m $s
    }
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

proc pluralRu {n one two five} {
    set n2 [expr {$n % 100}]
    set n1 [expr {$n % 10}]
    if {$n2 >= 5 && $n2 <= 20} {return "$n $five"}
    if {$n1 == 1} {return "$n $one"}
    if {$n1 in {2 3 4}} {return "$n $two"}
    return "$n $five"
}

proc simpleDictToJSON {dict indented} {
    ::json::write indented $indented
    set object {}
    dict for {k v} $dict {
	switch $k {
	    default {
		lappend object $k
		if {[regexp {^-?\d+(.\d+)?([eE][+-]?\d+)?$} $v]} {
		    lappend object $v
		} else {
		    lappend object [::json::write string $v]
		}
	    }
	}
    }
    ::json::write object {*}$object
}
