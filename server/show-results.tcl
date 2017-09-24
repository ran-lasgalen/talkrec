#!/bin/sh
# -*- tcl -*- \
exec tclsh "$0" ${1+"$@"}

proc showFile {textFile} {
    set metaFile [file rootname $textFile].meta
    if {[regexp {(\d{4})(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)_(\d+)_(\w+)} $textFile - y m d H M S siteId employeeId]} {
	set datetime "запись от $H:$M:$S $d.$m.$y, "
	set site "салон №$siteId, "
    } else {
	set datetime ""
	set site ""
    }
    set talks ""
    catch {
	set fh [open $metaFile r]
	while {[gets $fh line] > 0} {
	    if {[regexp {^name=(.*)} $line - name]} {
		set talks "говорит $name"
	    }
	}
	close $fh
    }
    puts "\n$datetime$site$talks"
    set fh [open $textFile r]
    puts [read $fh]
    close $fh
}

proc showNewFiles {} {
    set textFiles [glob -nocomplain -directory ~/queue *.text]
    foreach textFile $textFiles {
	if {![info exists ::seen($textFile)]} {
	    set ::seen($textFile) 1
	    showFile $textFile
	}
    }
    foreach textFile [array names ::seen] {
	if {![file exists $textFile]} {
	    unset ::seen($textFile)
	}
    }
    after 500 showNewFiles
}

puts "Здесь будут выводиться распознанные тексты по мере их распознавания"
puts ""
after idle showNewFiles
vwait forever
