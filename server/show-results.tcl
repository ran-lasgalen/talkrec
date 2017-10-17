#!/usr/bin/tclsh

set libtcldir [file join [file dirname [file dirname [file normalize [info script]]]] recorder libtcl]
source [file join $libtcldir common.tcl]

set ::sites [dict create]

proc showFile {textFile} {
    catch {set metaFile [dictFile [file rootname $textFile]]}
    if {[regexp {(\d{4})(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)_(\d+)_(\w+)} $textFile - y m d H M S siteId employeeId]} {
	set datetime "запись, начатая $H:$M:$S $d.$m.$y"
	if {[dict exists $::sites $siteId]} {
	    set site ", [dict get $::sites $siteId]"
	} else {
	    set site ", салон №$siteId"
	}
    } else {
	if {[info exists metaFile]} {
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
    catchDbg {set ::sites [readDict [configDictFile sites]]}
    set textFiles [lsort -decreasing -dictionary [glob -nocomplain -directory ~/queue *.text]]
    set content ""
    foreach textFile $textFiles {
	append content "[showFile $textFile]\n"
    }
    if {$content eq ""} {
	set content "<p>Пока распознанных текстов нет.</p>"
    }
    set title [clock format [clock seconds] -format "Результаты распознавания на %H:%M:%S %d.%m.%Y"]
    return "<html><head><title>$title</title></head><body>\n[links]\n<h1>$title</h1>\n$content\n</body></html>"
}

proc showReport {} {
    set title "В работе"
    set content "Report unavailable"
    catch {
	set h [open ~/queue/report r]
	set content [read $h]
	close $h
    }
    return "<html><head><title>$title</title></head><body>\n[links]\n<pre>\n$content\n</pre>\n</body></html>"
}

proc links {} {
    return "<div><a href='/'>результаты распознавания</a>&nbsp;&nbsp;&nbsp;&nbsp;<a href='/report'>в работе</a>&nbsp;&nbsp;&nbsp;&nbsp;<a href='/queue'>очередь</a></div>"
}

proc showQueue {} {
    set flags [lsort [glob -nocomplain -directory ~/queue *.flag]]
    set title [clock format [clock seconds] -format "Очередь на %H:%M:%S %d.%m.%Y"]
    append title ": [pluralRu [llength $flags] запись записи записей]"
    set content ""
    if {[llength $flags] > 0} {
	append content "<table border=1><tbody>\n<tr><th>имя</th><th>Кб</th></tr>\n"
	foreach flagFile $flags {
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
    }
    return "<html><head><title>$title</title></head><body>\n[links]\n<h1>$title</h1>\n$content\n</body></html>"
}

proc withHTTP {text} {
    if {[regexp {^\s*<html} $text]} {
	string cat "HTTP/1.0 200 OK\nContent-Type: text/html; charset=utf-8\n\n" $text
    } else {
	string cat "HTTP/1.0 200 OK\nContent-Type: text/plain; charset=utf-8\n\n" $text
    }
}

proc serveRequest {chan addr port} {
    fconfigure $chan -translation auto -buffering line
    set line [gets $chan]
    switch -regexp $line {
	{ /report } {
	    puts $chan [withHTTP [showReport]]
	}
	{ /queue } {
	    puts $chan [withHTTP [showQueue]]
	}
	default {
	    puts $chan [withHTTP [showNewFiles]]
	}
    }
    close $chan
}

socket -server serveRequest 8888
vwait forever
