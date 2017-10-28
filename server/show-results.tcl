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

proc showRecordStations {} {
    if {[catch {md5OfDir [file dirname $::libtcldir] check} myVersions]} {
	safelog {error $myVersion}
	set myVersions X
    }
    ::tdbc::postgres::connection create db -database talkrec
    try {
	set content "<table border=\"1\"><tbody>\n<tr><th>салон</th><th>IP</th><th>№</th><th>версия</th><th>состояние</th><th>на</th><th>смещение времени</th></tr>\n"
	db foreach row {select site.name, rs.* from record_station rs join site on site_id = site.id order by name, ip} {
	    append content "<tr>"
	    set version [dictGetOr Y $row version]
	    set state [dictGetOr "" $row state]
	    foreach k {name ip headset version state state_at time_diff} {
		if {$k in {state ip}} {
		    switch $state {
			работает { set class green }
			отключена { set class orange }
			default {
			    if {$version eq "ПО не установлено"} {set class orange} {set class red }
			}
		    }
		} elseif {$k eq "version"} {
		    if {$version in $myVersions} {set class green} {set class orange}
		} else {set class ""}
		if {$class eq ""} {set addclass ""} {set addclass " class=\"$class\""}
		append content "<td$addclass>[dictGetOr {&nbsp;} $row $k]</td>"
	    }
	    append content "</tr>\n"
	}
    } finally { catchDbg {db close} }
    set title [clock format [clock seconds] -format "Состояние станций записи на %H:%M:%S %d.%m.%Y"]
    set css {
	<style>
	.red { color: red }
	.green { color: green }
	.orange { color: orange }
	</style>
    }
    return "<html><head><title>$title</title>$css</head><body>\n[links]\n<h1>$title</h1>\n$content\n</body></html>"
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
		foreach d $prevnext {append content "<a href=\"/all/$d\">$d</a>&nbsp;&nbsp;&nbsp; "}
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

proc selectSite {} {
    set db [::tdbc::postgres::connection create db -database talkrec]
    try {
	set title "Записи сотрудников по салонам"
	set content ""
	set siteLinks [sitesWithRecordLinksList $db]
	if {[llength $siteLinks]} {
	    append content "<ul\n>" \
		[join [lmap sl $siteLinks {string cat "<li>" $sl "</li>"}] \n] \
		"\n</ul>\n"
	} else {
	    append content "<p>Записей нет</p>\n"
	}
    } finally {$db close}
    return "<html><head><title>$title</title></head><body>\n[links]\n<h1>$title</h1>\n$content\n</body></html>"
}

proc selectEmployee {siteId} {
    set db [::tdbc::postgres::connection create db -database talkrec]
    try {
	set siteName [lindex [$db allrows -as lists {select name from site where id = :siteId}] 0 0]
	set title "Записи сотрудников в салоне $siteName"
	set content [sitesWithRecordLinks $db]\n
	set speakers [speakersFromSite $db $siteId]
	if {[llength $speakers]} {
	    append content "<ul>\n"
	    foreach speaker $speakers {
		append content "<li><a href=\"/empl/$siteId/[dict get $speaker id]\">[dict get $speaker name]</a></li>\n"
	    }
	    append content "</ul>\n"
	} else {
	    append content "<p>Записей нет</p>\n"
	}
    } finally {$db close}
    return "<html><head><title>$title</title></head><body>\n[links]\n<h1>$title</h1>\n$content\n</body></html>"
}

proc employeeTalks {siteId employeeId {date ""}} {
    set db [::tdbc::postgres::connection create db -database talkrec]
    try {
	set siteName [lindex [$db allrows -as lists {select name from site where id = :siteId}] 0 0]
	set speakerName [lindex [$db allrows -as lists {select name from employee where id = :employeeId}] 0 0]
	if {$date eq ""} {
	    set date [lindex [$db allrows -as lists {select max(made_on) from talk where site_id = :siteId and employee_id = :employeeId}] 0 0]
	}
	if {$date eq ""} {
	    set prevnext {}
	} else {
	    set prevnext [concat \
			      [lreverse [$db allrows -as lists {select distinct made_on from talk where site_id = :siteId and employee_id = :employeeId and made_on < :date order by made_on desc limit 3}]] \
			      [list [list $date]] \
			      [$db allrows -as lists {select distinct made_on from talk where site_id = :siteId and employee_id = :employeeId and made_on > :date order by made_on limit 3}]]
	    # каждый элемент prevnext - одноэлементный список, состоящий из даты
	    set prevnext [lmap el $prevnext {
		set d [lindex $el 0]
		if {$d eq $date} {
		    list "" [dateRuAbbr $d]
		} else {
		    list "/empl/$siteId/$employeeId/$d" [dateRuAbbr $d]
		}
	    }]
	}
	set content [sitesWithRecordLinks $db]\n
	set speakers [speakersFromSite $db $siteId]
	append content [genLinks [lmap speaker $speakers {
	    set id [dict get $speaker id]
	    if {$id == $employeeId} continue
	    list "/empl/$siteId/$id" [familyIO [dict get $speaker name]]
	}]]
	if {[llength $prevnext]} {
	    append content [genLinks $prevnext]\n
	}
	set title "$speakerName в салоне $siteName"
	if {$date eq ""} {
	    append content "<p>Нет записей</p>\n"
	} else {
	    append title ", записи за [dateRu $date]"
	    $db foreach row {select talk, started_at from talk where site_id = :siteId and employee_id = :employeeId and made_on = :date order by started_at} {
		dict with row {
		    if {![regexp {\d\d:\d\d:\d\d} $started_at tm]} {set tm $started_at}
		    append content "<p>\n<em>$tm:</em> $talk</p>\n"
		}
	    }
	}
    } finally {$db close}
    return "<html><head><title>$title</title></head><body>\n[links]\n<h1>$title</h1>\n$content\n</body></html>"
}

proc familyIO {name} {
    try {
	set res {}
	foreach w $name {
	    if {[llength $res]} {lappend res [string cat [string index $w 0] .]} {lappend res $w}
	}
	return $res
    } on error {} {return $name}
}

proc dateRuAbbr {date} {dateRuDict $date {01 янв 02 фев 03 мар 04 апр 05 мая 06 июн 07 июл 08 авг 09 сен 10 окт 11 ноя 12 дек}}

proc dateRu {date} {dateRuDict $date {01 января 02 февраля 03 марта 04 апреля 05 мая 06 июня 07 июля 08 августа 09 сентября 10 октября 11 ноября 12 декабря}}

proc dateRuDict {date dict} {
    if {![regexp {^(\d\d\d\d)-(\d\d)-(\d\d)$} $date - y m d]} {return $date}
    if {[clock format [clock seconds] -format "%Y"] eq $y} {set yt ""} {set yt " $y"}
    if {[catch {dict get $dict $m} mt]} {return $date}
    string cat $d " " $mt $yt
}

proc speakersFromSite {db siteId} {
    $db allrows {select id,name from employee where id in (select distinct employee_id from talk where site_id = :siteId) order by name}
}

proc sitesWithRecordLinks {db} {
    string cat {<div class="sitelinks">} [join [sitesWithRecordLinksList $db] "&nbsp;&nbsp;&nbsp; "] "</div>"
}

proc sitesWithRecordLinksList {db} {
    set sites [$db allrows {select id,name from site where id in (select distinct site_id from talk) order by name}]
    lmap site $sites {
	string cat {<a href="/empl/} [dict get $site id] {"><nobr>} [dict get $site name] "</nobr></a>"
    }
}

proc withHTTP {text} {
    set cl "Content-Length: [string bytelength $text]\n"
    if {[regexp {^\s*<html} $text]} {
	string cat "HTTP/1.0 200 OK\nContent-Type: text/html; charset=utf-8\n$cl\n" $text
    } else {
	string cat "HTTP/1.0 200 OK\nContent-Type: text/plain; charset=utf-8\n$cl\n" $text
    }
}

proc genLinks {linkPairs} {
    set links [lmap lp $linkPairs {
	foreach {link text} $lp break
	if {$link eq ""} {
	    string cat "<b><nobr>" [htmlEscape $text] "</nobr></b>"
	} else {
	    string cat "<a href=\"" $link "\"><nobr>" [htmlEscape $text] "</nobr></a>"
	}
    }]
    string cat \
	"<div class=\"links\">" \
	[join $links "&nbsp;&nbsp;&nbsp; "] \
	"</div>"
}

proc links {} {
    genLinks {
	{/empl {записи сотрудников}}
	{/all {результаты распознавания}}
	{/report {в работе}}
	{/queue очередь}
	{/stations {станции записи}}
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
	{ /stations } {
	    puts $chan [withHTTP [showRecordStations]]
	}
	{ /all } {
	    puts $chan [withHTTP [showRecords]]
	}
	{ /all/(\d\d\d\d-\d\d-\d\d) } {
	    puts $chan [withHTTP [showRecords [lindex $matches 1]]]
	}
	{ /empl } {
	    puts $chan [withHTTP [selectSite]]
	}
	{ /empl/(\d+) } {
	    puts $chan [withHTTP [selectEmployee [lindex $matches 1]]]
	}
	{ /empl/(\d+)/(\d+) } {
	    puts $chan [withHTTP [employeeTalks [lindex $matches 1] [lindex $matches 2]]]
	}
	{ /empl/(\d+)/(\d+)/(\d\d\d\d-\d\d-\d\d) } {
	    puts $chan [withHTTP [employeeTalks [lindex $matches 1] [lindex $matches 2] [lindex $matches 3]]]
	}
	{ / } {
	    puts $chan [withHTTP [selectSite]]
	}
	default {
	    puts $chan [withHTTP ""]
	}
    }
    close $chan
}

getOptions - {}
socket -server serveRequest 8888
vwait forever
