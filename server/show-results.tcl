#!/usr/bin/tclsh

set libtcldir [file join [file dirname [file dirname [file normalize [info script]]]] recorder libtcl]
source [file join $libtcldir common.tcl]
package require tdbc
package require tdbc::postgres

set ::sites [dict create]
set ::siteIdMap [dict create]
set ::employeeIdMap [dict create]

proc showFile {textFile} {
    catch {set metaFile [dictFile [file rootname $textFile]]}
    if {[regexp {(\d{4})(\d\d)(\d\d)_(\d\d)(\d\d)(\d\d)_(?:site)?(\d+)_(\w+)} $textFile - y m d H M S siteM employeeId]} {
	set datetime "запись, начатая $H:$M:$S $d.$m.$y"
	if {[catch {dict get $::siteIdMap $siteM} siteId]} {set siteId $siteM}
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

proc showRecords {{date {}}} {
    ::tdbc::postgres::connection create db -database talkrec
    try {
	if {$date eq ""} {set date [lindex [db allrows -as lists {select max(made_on) from talk}] 0 0]}
	if {$date eq ""} {set content "<p>Пока записей в базе данных нет</p>"} else {
	    set content ""
	    set prevdates [lindex [db allrows -as lists {select max(made_on) from talk where made_on < :date}] 0]
	    set nextdates [lindex [db allrows -as lists {select min(made_on) from talk where made_on > :date}] 0]
	    set prevnext [concat $prevdates $nextdates]
	    if {[llength $prevnext]} {
		append content "<div class=\"prevnext\">"
		foreach d $prevnext {append content "<a href=\"/$d\">$d</a>&nbsp;&nbsp;&nbsp;&nbsp;"}
		append content "</div>\n"
	    }
	    set records [db allrows {select talk.*, employee.name as ename, site.name as sname from talk left outer join site on talk.site_id = site.id left outer join employee on talk.employee_id = employee.id where made_on = :date order by started_at}]
	    if {[llength $records]} {
		foreach record $records {
		    if {[catch {showRecord $record} html dbg]} {
			debugStackTrace $dbg
			append content "<div class=\"error\">ошибка форматирования записи [htmlEscape $record]: $html</div>\n"
		    } else {
			append content "$html\n"
		    }
		}
	    } else {
		append content "<p>Записей за $date не обнаружено</p>"
	    }
	}
    } finally { catchDbg {db close} }
    set title [clock format [clock seconds] -format "Результаты распознавания за $date на %H:%M:%S %d.%m.%Y"]
    return "<html><head><title>$title</title></head><body>\n[links]\n<h1>$title</h1>\n$content\n</body></html>"
}

proc showRecord {record} {
    set content "<div class=\"record\">\n"
    set title {}
    catch {
	set startedAt [dict get $record started_at]
	catch {set startedAt [clock format [clock scan $startedAt -format "%Y-%m-%d %H:%M:%S%z"] -format "%H:%M:%S %d.%m.%Y"]}
    }
    if {[dict exists $record id]} {
	lappend title "запись №[dict get $record id]"
    } else {
	lappend title "запись без номера"
    }
    if {[info exists startedAt]} {
	lappend title $startedAt
    }
    if {[dict exists $record sname]} {
	lappend title [htmlEscape [dict get $record sname]]
    } elseif {[dict exists $record site_id]} {
	lappend title "салон №[dict get $record site_id]"
    }
    if {[dict exists $record ename]} {
	lappend title "говорит [htmlEscape [dict get $record ename]]"
    }
    append content "<h3>[join $title {, }]:</h3>"
    catchDbg {append content "<p>Текст: [htmlEscape [dict get $record talk]]</p>\n"}
    if {[dict exists $record extra]} {
	catchDbg {
	    set extra [::json::json2dict [dict get $record extra]]
	    if {[dict exists $extra problem]} {
		append content "<p><i>[htmlEscape [dict get $extra problem]]</i></p>\n"
	    }
	}
    }
    append content "</div>"
}

proc showNewFiles {} {
    catchDbg {set ::sites [readDict [configDictFile sites]]}
    catchDbg {
	set rd [readDict [configDictFile site-emp-maps]]
	if {[dict exists $rd siteMap]} {set ::siteIdMap [dict get $rd siteMap]}
	if {[dict exists $rd employeeMap]} {set ::employeeIdMap [dict get $rd employeeMap]}
    }
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
    switch -regexp -matchvar matches $line {
	{ /report } {
	    puts $chan [withHTTP [showReport]]
	}
	{ /queue } {
	    puts $chan [withHTTP [showQueue]]
	}
	{ /(\d\d\d\d-\d\d-\d\d) } {
	    puts $chan [withHTTP [showRecords [lindex $matches 1]]]
	}
	default {
	    puts $chan [withHTTP [showRecords]]
	}
    }
    close $chan
}

getOptions - {}
socket -server serveRequest 8888
vwait forever
