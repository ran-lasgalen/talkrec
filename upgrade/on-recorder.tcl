set ::installerDir [file dirname [file normalize [info script]]]

proc main {} {
    getOptions - {
	{--sudo-pw "" "password for sudo if it is needed"}
	{--reconfigure "Только изменить конфигурацию"}
    }
    set ::sudoPassword $::opt(-sudo-pw)
    # добываем адрес сервера из приехавших с нами конфигов
    set recorderConf [readDict [file join $::installerDir recorder.json]]
    set serverAddr [dict get $recorderConf server]
    # и копируем их в configDir
    run file copy -force -- {*}[glob -directory $::installerDir *.json] $::configDir
    if {![dict exists $::paths recorderBin]} {
	dict set ::paths recorderBin [file normalize ~/recorder]
    }
    if {!$::opt(-reconfigure)} {
	# втягиваем скрипты
	runExec rsync -av --delete rsync://$serverAddr:8873/recorder/ [dict get $::paths recorderBin]
	installServiceFiles [glob -directory [file join [dict get $::paths recorderBin] example] *.service]
    }
    catchDbg {runExec killall record_manager}
    catchDbg {runExec pulseaudio --kill}
    catchDbg {runExec pulseaudio --start}
    catchDbg {runExec systemctl --user restart recorder.service}
}

runMain
