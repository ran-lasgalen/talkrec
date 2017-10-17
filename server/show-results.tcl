#!/usr/bin/tclsh

set libtcldir [file join [file dirname [file dirname [file normalize [info script]]]] recorder libtcl]
source [file join $libtcldir common.tcl]

proc showFile {textFile} {
    set metaFile [dictFile [file rootname $textFile]]
    if {[regexp {(\d{4})(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)_(\d+)_(\w+)} $textFile - y m d H M S siteId employeeId]} {
	set datetime "запись, начатая $H:$M:$S $d.$m.$y"
	set site ", салон №$siteId"
    } else {
	if {[file exists $metaFile]} {
	    set datetime [clock format [file mtime $metaFile] -format "запись, завершенная %H:%M:%S %d.%m.%Y"]
	} else {
	    set datetime [clock format [file mtime $textFile] -format "запись, распознанная %H:%M:%S %d.%m.%Y"]
	}
	set site ""
    }
    set talks ""
    catch {
	set meta [readDict $metaFile]
	if {[dict exists $meta name]} {
	    set talks ", говорит [dict get $meta name]"
	}
    }
    set content "Не удалось прочесть файл $textFile"
    catch {
	set fh [open $textFile r]
	set content [read $fh]
	close $fh
    }
    set header [htmlEscape "$datetime$site$talks:"]
    set content [htmlEscape $content]
    return "<div style='margin-bottom: 1ex;'>\n<h2>$header</h2>\n<p>$content</p>\n</div>"
}

proc htmlEscape {text} {
    set res $text
    foreach {re sub} {& {\&amp;} < {\&lt;} > {\&gt;}} {
	regsub -all $re $res $sub res
    }
    return $res
}

proc showNewFiles {} {
    set textFiles [lsort -decreasing -dictionary [glob -nocomplain -directory ~/queue *.text]]
    set content ""
    foreach textFile $textFiles {
	append content "[showFile $textFile]\n"
    }
    if {$content eq ""} {
	set content "<p>Пока распознанных текстов нет.</p>\n"
    }
    set title [clock format [clock seconds] -format "Результаты распознавания на %H:%M:%S %d.%m.%Y"]
    return "<html><head><title>$title</title></head><body>\n<h1>$title</h1>\n$content</body></html>"
}

proc showReport {} {
    set content "Report unavailable"
    catch {
	set h [open ~/queue/report r]
	set content [read $h]
	close $h
    }
    return $content
}

proc showQueue {} {
    set flags [lsort [glob -nocomplain -directory ~/queue *.flag]]
    set title [clock format [clock seconds] -format "Очередь на %H:%M:%S %d.%m.%Y"]
    append title ": [llength flags] файлов"
    set content "<table><tbody>\n<tr><th>имя</th><th>Кб</th></tr>\n"
    foreach flag $flags {
	set soundFile [file rootname $flagFile]
	set soundFileName [file tail $soundFile]
	if {[file exists $soundFile]} {
	    set size [expr {([file size $soundFile] + 512) / 1024}]
	} else {
	    set size —
	}
	append content "<tr><td>$soundFileName</td><td>$size</td></tr>\n"
    }
    append content "</tbody></table>\n"
    return "<html><head><title>$title</title></head><body>\n<h1>$title</h1>\n$content</body></html>"
}

proc serveRequest {chan addr port} {
    fconfigure $chan -translation auto -buffering line
    set line [gets $chan]
    switch -regexp $line {
	{ /report } {
	    puts $chan "HTTP/1.0 200 OK\nContent-Type: text/plain; charset=utf-8\n\n[showReport]"
	}
	{ /queue } {
	    puts $chan "HTTP/1.0 200 OK\nContent-Type: text/html; charset=utf-8\n\n[showQueue]"
	}
	default {
	    puts $chan "HTTP/1.0 200 OK\nContent-Type: text/html; charset=utf-8\n\n[showNewFiles]"
	}
    }
    close $chan
}

socket -server serveRequest 8888
vwait forever
