set ::installerDir [file dirname [file normalize [info script]]]

proc main {} {
    getOptions - {
	{--sudo-pw "" "password for sudo if it is needed"}
    }
    set ::sudoPassword $::opt(-sudo-pw)
    # создаем конфигурационую директорию
    run file mkdir $::configDir
    run file attributes $::configDir -permissions 0700
    # добываем адрес сервера из приехавших с нами конфигов
    set recorderConf [readDict [file join $::installerDir recorder.json]]
    set serverAddr [dict get $recorderConf server]
    # и копируем их в configDir
    run file copy -force -- {*}[glob -directory $::installerDir *.json] $::configDir
    # создаем конфиг путей
    set talkrecDir [file normalize ~/talkrec]
    set ::scriptDir [file join $talkrecDir recorder]
    file mkdir $::scriptDir
    if {![dict exists $::paths talks]} {dict set ::paths talks [file normalize ~/talks]}
    if {![dict exists $::paths recorderBin]} {dict set ::paths recorderBin $::scriptDir}
    createFileViaTmp [configFile paths.json] [simpleDictToJSON $::paths 1]
    # обеспечиваем работу systemd с юзерскими конфигами
    enableLinger
    set serviceDir [file normalize ~/.config/systemd/user]
    run file mkdir $serviceDir
    # доставляем нужные пакеты (кроме nodm, его потом отдельно)
    set debs [debsYetToInstall {tcl tcllib tk bwidget rsync psmisc adduser sox pulseaudio pulseaudio-utils spectrwm}]
    if {[llength $debs] > 0} {sudoWithPw apt-get install --yes {*}$debs}
    if {"audio" ni [readFile {| groups}]} {sudoWithPw adduser $::tcl_platform(user) audio}
    # втягиваем скрипты
    runExec rsync -av --delete rsync://$serverAddr:8873/recorder/ $::scriptDir
    foreach oldFile {recorder.yaml record_manager.yaml employees.yaml recorder.tcl sound_sender.yaml sound_sender.bash} {file delete -- [file join $::configDir $oldFile]}
    # отстреливаем, если кто работал
    catchDbg {runExec killall demo_run recorder sound_sender record_manager}
    # перезапускаем pulseaudio, чтобы отцепить от иксов
    catchDbg {runExec pulseaudio --kill}
    runExec pulseaudio --start
    # настраиваем запуск recorder и sound_sender
    set services {recorder sound_sender}
    foreach service $services {
	set content [list \
			 {[Unit]} \
			 "AssertPathExists=[file join $::scriptDir $service]" \
			 "" \
			 {[Service]} \
			 {WorkingDirectory=~} \
			 "ExecStart=[file join $::scriptDir $service]" \
			 "" \
			 {[Install]} \
			 {WantedBy=default.target}]
	createFileViaTmp [file join $serviceDir $service.service] [join $content "\n"]
    }
    runExec systemctl --user daemon-reload
    foreach service $services {
	runExec systemctl --user enable $service
	catchDbg {runExec systemctl --user stop $service}
	runExec systemctl --user start $service
    }
    createFileViaTmp ~/.xsession "#!/bin/sh\nspectrwm &\n[file join $::scriptDir record_manager]"
    set debs [debsYetToInstall nodm]
    if {"nodm" in $debs} {
	createFileViaTmp [file join $::installerDir nodm.preseed] "nodm nodm/enabled boolean true\nnodm nodm/user string user"
	sudoWithPw debconf-set-selections [file join $::installerDir nodm.preseed]
	catchDbg {runExec sudo apt-get remove --yes lightdm}
	runExec sudo apt-get install --yes {*}$debs
    }
    file delete -force $::installerDir
}

proc enableLinger {} {
    if {[catch {readFile [list | loginctl show-user $::tcl_platform(user)]} showUser]} {
	set lingerEnabled 0
    } else {
	set lingerEnabled [regexp Linger=yes $showUser]
    }
    if {!$lingerEnabled} {sudoWithPw loginctl enable-linger $::tcl_platform(user)}
}

try {main} on error {err dbg} {debugStackTrace $dbg; puts stderr "\n$err"; exit 2}
