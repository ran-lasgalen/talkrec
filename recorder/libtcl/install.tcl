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
	run file rename -force $tmpFile $serviceFile
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

proc installServiceFiles {files} {
    set systemdDir ~/.config/systemd/user
    if {![dict exists $::paths serverBin]} {
	dict set ::paths serverBin [file normalize ~/talkrec/server]
    }
    if {![dict exists $::paths recorderBin]} {
	dict set ::paths recorderBin [file normalize ~/talkrec/recorder]
    }
    if {![dict exists $::paths queue]} {
	dict set ::paths queue [file normalize ~/queue]
    }
    if {![dict exists $::paths talks]} {
	dict set ::paths talks [file normalize ~/talks]
    }
    set substs [dict merge [dict create configDir $::configDir] $::paths]
    set services {}
    foreach template $files {
	set sf [file tail $template]
	lappend services $sf
	catchDbg {runExec systemctl --user stop $sf}
	createFileViaTmp [file join $systemdDir $sf] [substFromDict $substs [readFile $template]]
    }
    runExec systemctl --user daemon-reload
    foreach service $services {
	runExec systemctl --user enable $service
	runExec systemctl --user start $service
    }
}

proc siteAndHeadsetForIP {db ip} {
    set result [$db allrows {select headset, site_id from record_station where ip = :ip}]
    switch [llength $result] {
	1 {set conf [lindex $result 0]}
	0 {error "База данных ничего не знает про станцию с IP $ip"}
	default {error "В базе данных несколько записей про станцию с IP $ip:\n$result"}
    }
    if {![dict exists $conf headset]} {error "Неизвестен номер гарнитуры для $ip"}
    if {![dict exists $conf site_id]} {error "Неизвестен салон, в котором находится $ip"}
    return $conf
}

proc genEmployeesConfig {db siteId indented} {
    set employees {}
    $db foreach -as lists r {select name, id from employee, site_employee where id = employee_id and site_id = :siteId order by name} {lappend employees {*}$r}
    simpleDictToJSON $employees $indented
}

proc genRecordManagerConfig {db siteId serverAddr indented} {
    ::json::write indented $indented
    set recorders [$db allrows -as lists {select ip from record_station where site_id = :siteId}]
    set recordersJSON [::json::write array {*}[lmap el $recorders {::json::write string $el}]]
    ::json::write object server [::json::write string $serverAddr] siteId [scalarToJSON $siteId] recorders $recordersJSON
}

proc genRecorderConfig {ipConf serverAddr indented} {
    set user site[dict get $ipConf site_id]
    ::json::write indented $indented
    ::json::write object \
	headset [dict get $ipConf headset] \
	recorderPort 17119 \
	soundSystem [::json::write string pulse] \
	deviceRE [::json::write string input.usb-GN_Netcom_A_S_Jabra_PRO_9460] \
	server [::json::write string $serverAddr] \
	user [::json::write string $user] \
	password [::json::write string [getSiteRsyncPassword $user]] \
	workHours [::json::write array 10 21] \
	auto [::json::write object \
		  autoMode [::json::write string silence] \
		  aboveDuration 0.5 \
		  aboveLevel [::json::write string 0.1%] \
		  belowDuration 10.0 \
		  belowLevel [::json::write string 2%]]
}

proc getServerAddr {} {
    set pipe [open {| ip -o ad ls scope global} r]
    try {
	while {[gets $pipe line] >= 0} {
	    if {[regexp {\sinet\s+(\d+\.\d+\.\d+\.\d+)} $line - ip]} {
		puts -nonewline "Адрес сервера - $ip? (YД/nн) "
		flush stdout
		gets stdin reply
		if {[regexp {^\s*([yYдД]|$)} $reply]} {return $ip}
	    }
	}
	error "getServerAddr: годного адреса сервера не нашлось"
    } finally {
	close $pipe
    }
}

proc getSiteRsyncPassword {user} {
    set h [open [configFile rsyncd.secrets] r]
    try {
	while {[gets $h line] >= 0} {
	    foreach {login password} [split $line :] break
	    if {[string trim $login] ne $user} continue
	    set password [string trim $password]
	    if {$password eq ""} {error "Пароль для $login пустой"}
	    return $password
	}
    } finally {close $h}
    set h [open /dev/urandom r]
    try {set password [binary encode hex [read $h 16]]} finally {close $h}
    set h [open [configFile rsyncd.secrets] a]
    try {puts $h "${user}:$password"} finally {close $h}
    return $password
}
