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

proc whereClause {keyword args} {
    set conds [lmap c $args {if {$c eq ""} continue else {string cat ( $c )}}]
    if {[llength $conds]} {
	if {$keyword ne ""} {set keyword [string cat $keyword " "]}
	string cat $keyword [join $conds " and "] " "
    } else {return ""}
}

# Возвращает пару (дата, список пар дата-целое), где целое меньше нуля, если
# дата раньше запрошенной, равно нулю, если равна, и больше нуля, если дата
# больше запрошенной. Если дата не задана, ищется (и возвращается) самая
# свежая. Если не найдена, возвращает пустую дату и пустой список. Если дата
# задана, НЕ проверяется, есть ли соответствие в базе.
# db - соединение с базой данных
# where - содержимое WHERE
# subst - словарь подстановок для $where
# date - искомая дата (если пусто, ищется самая свежая)
# n - максимальное количество дат до и после
proc talkDateSeries {db where substs {date ""} {n 3}} {
    if {$date eq ""} {
	set date [lindex [$db allrows -as lists "select max(made_on) from talk [whereClause where $where]" $substs] 0 0]
    }
    if {$date eq ""} {return {"" {}}}
    dict set substs date $date
    dict set substs n $n
    set datesBefore [$db allrows -as lists [string cat "select distinct made_on from talk " [whereClause where $where "made_on < :date"] " order by made_on desc limit :n"] $substs]
    set datesAfter [$db allrows -as lists [string cat "select distinct made_on from talk " [whereClause where $where "made_on > :date"] " order by made_on limit :n"] $substs]
    list $date [concat \
		    [lmap d [lreverse $datesBefore] {lappend d -1}] \
		    [list [list $date 0]] \
		    [lmap d $datesAfter {lappend d 1}]]
}

proc phraseExplained {date siteId phraseId} {
    set db [::tdbc::postgres::connection create db -database talkrec]
    try {
	set siteName [lindex [$db allrows -as lists {select name from site where id = :siteId}] 0 0]
	if {$siteName eq ""} {set siteName "№$siteId"}
	set phrase [lindex [$db allrows {select description, regexp from phrase where id = :phraseId}] 0]
	set title "В записях салона $siteName за [dateRu $date]"
	if {$phrase eq ""} {
	    set content "<p class='red'>Выражение №$phraseId не обнаружено в базе данных.</p>"
	} else {
	    set content "<p>Выражение: [htmlEscape [dict get $phrase description]]</p>"
	    set re [dict get $phrase regexp]
	    if {[catch {regexp $re ""} err dbg]} {
		debugStackTrace $dbg
		safelog {error "Ошибка регулярного выражения фразы №$phraseId ($re): $err"}
		append content "<p class='red'>Некорректное регулярное выражение [htmlEscape $re]</p>"
	    } else {
		$db foreach row {select talk.id, talk, started_at, name from talk join phrase_talk on phrase_talk.talk_id = talk.id left outer join employee on employee_id = employee.id where site_id = :siteId and made_on = :date and phrase_id = :phraseId} {
		    set name [dictGetOr "" $row name]
		    if {$name ne ""} {set name ", $name"}
		    set startedAt ""
		    catch {
			set startedAt [dict get $row started_at]
			catch {set startedAt [clock format [clock scan $startedAt -format "%Y-%m-%d %H:%M:%S%z"] -format "%H:%M:%S"]}
		    }
		    append content "\n<div><em>$startedAt$name:</em><br />\n"
		    if {[catch {regsub -all $re [htmlEscape [dict get $row talk]] {<b>&</b>}} res dbg]} {
			debugStackTrace $dbg
			safelog {error "Ошибка регулярной замены фразы №phraseId в записи №[dictGetOr {} $row id]"}
			append content [htmlEscape [dictGetOr "" $row talk]]
		    } else {
			append content $res
		    }
		    append content "\n</div>"
		}
	    }
	}
    } finally {$db close}
    set css {
	<style>
	.red { color: red }
	.green { color: green }
	.orange { color: orange }
	.left { text-align: left }
	.right { text-align: right }
	.center { text-align: center }
	</style>
    }
    return "<html><head><title>$title</title>$css</head><body>\n[links]\n<h1>$title</h1>\n$content\n</body></html>"
}

proc summaryExplained {date siteId catId desired} {
    set db [::tdbc::postgres::connection create db -database talkrec]
    try {
	set siteName [lindex [$db allrows -as lists {select name from site where id = :siteId}] 0 0]
	if {$siteName eq ""} {set siteName "№$siteId"}
	set category [lindex [$db allrows -as lists {select title from phrase_category where id = :catId}] 0 0]
	if {$category eq ""} {set category "№$catId"}
	if {$desired eq "t"} {set desiredRu "Желательные"} else {set desiredRu "Нежелательные"}
	set title "$desiredRu выражения категории $category в записях салона $siteName за [dateRu $date]"
	set content "<table border='1'><tbody>\n<tr><th>выражение</th><th>кол-во</th></tr>\n"
	$db foreach row {select p.id, p.description, sum(pt.n) as catches from phrase p join phrase_talk pt on p.id = pt.phrase_id join talk t on t.id = pt.talk_id where t.site_id = :siteId and t.made_on = :date and p.category_id = :catId and p.desired = :desired group by p.id, p.description order by p.description} {
	    append content "<tr><td><a href='/explain/$date/$siteId/[dict get $row id]'>[dict get $row description]</a></td><td class='right'>[dictGetOr 0 $row catches]</td></tr>\n"
	}
	append content "</tbody></table>"
    } finally {$db close}
    set css {
	<style>
	.red { color: red }
	.green { color: green }
	.orange { color: orange }
	.left { text-align: left }
	.right { text-align: right }
	.center { text-align: center }
	</style>
    }
    return "<html><head><title>$title</title>$css</head><body>\n[links]\n<h1>$title</h1>\n$content\n</body></html>"
}

proc summary {date} {
    set db [::tdbc::postgres::connection create db -database talkrec]
    try {
	foreach {date dateSeries} [talkDateSeries $db "" {} $date] break
	set prevnext [lmap el $dateSeries {
	    foreach {d i} $el break
	    set dr [dateRuAbbr $d]
	    if {$i} {list "/summary/$d" $dr} else {list "" $dr}
	}]
	set content ""
	if {[llength $prevnext]} {
	    append content [genLinks $prevnext]\n
	}
	if {$date eq ""} {
	    set title "Сводные данные"
	    append content "<p>Сводные данные отсутствуют</p>"
	} else {
	    set title "Сводные данные за [dateRu $date]"
	    set sites [$db allrows {select id,name from site where id in (select distinct site_id from talk) order by name}]
	    set categories [phraseCategories $db]
	    set catIds [lmap cat $categories {dict get $cat id}]
	    set matrix [dict create]
	    foreach stat [phraseStats $db $date] {
		set siteId [dict get $stat site_id]
		set catId [dict get $stat category_id]
		set desired [dict get $stat desired]
		set catches [dict get $stat catches]
		if {![dict exists $matrix $siteId]} {dict set matrix $siteId [dict create]}
		if {![dict exists $matrix $siteId $catId]} {dict set matrix $siteId $catId [dict create]}
		dict set matrix $siteId $catId $desired $catches
	    }
	    append content "<table border='1'><tbody>\n<tr><th>Салон</th>"
	    foreach cat $categories {append content "<th>[dictGetOr {&nbsp;} $cat title]</th>"}
	    append content "</tr>\n"
	    foreach site $sites {
		append content "<tr><th class='left'>[dictGetOr {&nbsp;} $site name]</th>"
		set siteId [dict get $site id]
		foreach catId $catIds {
		    set nt [dictGetOr 0 $matrix $siteId $catId t]
		    set nts "<span class='green'>$nt</span>"
		    if {$nt > 0} {set nts "<a href='/summary/$date/$siteId/$catId/t'>$nts</a>"}
		    set nf [dictGetOr 0 $matrix $siteId $catId f]
		    set nfs "<span class='red'>$nf</span>"
		    if {$nf > 0} {set nfs "<a href='/summary/$date/$siteId/$catId/f'>$nfs</a>"}
		    append content "<td class='center'>$nts / $nfs</td>"
		}
		append content "</tr>\n"
	    }
	    append content "</tbody></table>"
	}
    } finally {$db close}
    set css {
	<style>
	.red { color: red }
	.green { color: green }
	.orange { color: orange }
	.left { text-align: left }
	.right { text-align: right }
	.center { text-align: center }
	</style>
    }
    return "<html><head><title>$title</title>$css</head><body>\n[links]\n<h1>$title</h1>\n$content\n</body></html>"
}

proc phraseCategories {db} {$db allrows {select id, title from phrase_category order by ord}}

proc phraseStats {db date} {
    set query {select t.site_id, p.category_id, p.desired, sum(pt.n) as catches from talk t join phrase_talk pt on t.id = pt.talk_id join phrase p on p.id = pt.phrase_id where t.made_on = :date group by t.site_id, p.category_id, p.desired}
    db allrows $query
}

proc employeeTalks {siteId employeeId {date ""}} {
    set db [::tdbc::postgres::connection create db -database talkrec]
    try {
	set siteName [lindex [$db allrows -as lists {select name from site where id = :siteId}] 0 0]
	set speakerName [lindex [$db allrows -as lists {select name from employee where id = :employeeId}] 0 0]
	foreach {date dateSeries} [talkDateSeries $db {site_id = :siteId and employee_id = :employeeId} [dict create siteId $siteId employeeId $employeeId] $date] break
	set prevnext [lmap el $dateSeries {
	    foreach {d i} $el break
	    set dr [dateRuAbbr $d]
	    if {$i} {list "/empl/$siteId/$employeeId/$d" $dr} else {list "" $dr}
	}]
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
	{/summary {сводные данные}}
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
	{ /summary } {
	    puts $chan [withHTTP [summary ""]]
	}
	{ /summary/(\d\d\d\d-\d\d-\d\d) } {
	    puts $chan [withHTTP [summary [lindex $matches 1]]]
	}
	{ /summary/(\d\d\d\d-\d\d-\d\d)/(\d+)/(\d+)/([tf]) } {
	    puts $chan [withHTTP [summaryExplained [lindex $matches 1] [lindex $matches 2] [lindex $matches 3] [lindex $matches 4]]]
	}
	{ /explain/(\d\d\d\d-\d\d-\d\d)/(\d+)/(\d+) } {
	    puts $chan [withHTTP [phraseExplained  [lindex $matches 1] [lindex $matches 2] [lindex $matches 3]]]
	}
	{ / } {
	    puts $chan [withHTTP [summary ""]]
	}
	default {
	    puts $chan [withHTTP ""]
	}
    }
    catch {close $chan}
}

getOptions - {}
socket -server serveRequest 17121
vwait forever
