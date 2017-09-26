#!/usr/bin/tclsh

package require Tcl 8.5
package require yaml
package require log
package require cmdline

proc main {} {
    set options {
	{dry-run "Не выполнять команды, меняющие ситуацию, а только показывать их"}
	{debug "Показывать отладочный вывод"}
    }
    array set ::opt [::cmdline::getoptions ::argv $options]
    ::log::lvSuppressLE emergency 0
    if {!$::opt(debug)} {::log::lvSuppress debug}
    if {$::opt(dry-run)} {set ::dryRun 1}
    set ::configFile [lindex $::argv 0]
    if {$::configFile eq ""} {set ::configFile ~/.config/talkrec/sound_sender.yaml}
    set ::mtime 0
    if {![rereadConfig]} {exit 2}
    after idle runQueue
    vwait forever
}

proc errorListWhile {context errors} {
    set res ""
    append res $context ":"
    foreach err $errors {append res "\n- " $err}
    return $res
}

proc rereadConfig {} {
    if {[catch {file mtime $::configFile} mtime]} {
	::log::log error "Файл $::configFile не существует или недоступен."
	return false
    }
    if {$mtime > $::mtime} {
	set ::mtime $mtime; # В случае ошибки чтения тоже не перечитываем повторно, если файл не изменился, ибо смысл?
	if {[catch {readConfig $::configFile} res]} {
	    ::log::log error [errorListWhile "Ошибки при чтении файла конфигурации $::configFile" $res]
	    return false;
	} else {
	    set ::config $res
	}
    }
    return true
}

proc readConfig {configFile} {
    set conf [::yaml::yaml2dict -file $configFile]
    set errors {}
    if {![dict exists $conf user]} {lappend errors "не указано имя пользователя для rsync (ключ user)"}
    if {![dict exists $conf password]} {lappend errors "не указан пароль для rsync (ключ password)"}
    if {![dict exists $conf server]} {lappend errors "не указан сервер распознавания (ключ server)"}
    if {[llength $errors] > 0} {error $errors}
    if {![dict exists $conf workdir]} {
	set wd [file normalize .]
	::log::log notice "рабочая папка (ключ workdir) не указана, установлена в $wd"
	dict set conf workdir $wd
    }
    return $conf
}

proc runQueue {} {
    rereadConfig
    set soundFiles [glob -nocomplain -directory [file normalize [dict get $::config workdir]] *.wav]
    foreach soundFile $soundFiles {sendSound $soundFile}
    after 12000 runQueue
}

proc sendSound {soundFile} {
    set metaFile $soundFile.meta
    set flagFile $soundFile.flag
    if {![file exists $metaFile]} return
    if {[catch {
	set ::env(RSYNC_PASSWORD) [dict get $::config password]
	set user [dict get $::config user]
	set server [dict get $::config server]
	set fh [open $flagFile w]
	close $fh
	run exec rsync -t -- $soundFile $metaFile "rsync://$user@$server:8873/queue"
	run exec rsync -t -- $flagFile "rsync://$user@$server:8873/queue"
	run file delete -- $soundFile $metaFile $flagFile
    } err]} {
	::log::log error $err
    }
}

proc run {args} {
    if {[lindex $args 0] eq "exec"} {
	set which "shell"
	set report [lrange $args 1 end]
    } else {
	set which "tcl"
	set report $args
    }
    if {[info exists ::dryRun] && $::dryRun} {
	::log::log notice [concat [list Would run $which command:] $report]
    } else {
	::log::log info [concat [list $which command:] $report]
	{*}$args
    }
}

main
