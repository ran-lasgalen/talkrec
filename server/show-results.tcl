#!/usr/bin/tclsh

package require Tcl 8.5
package require yaml

proc showFile {textFile} {
    set metaFile [file rootname $textFile].yaml
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
	set meta [::yaml::yaml2dict -file $metaFile]
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

proc serveRequest {chan addr port} {
    fconfigure $chan -translation auto -buffering line
    set line [gets $chan]
    puts $chan "HTTP/1.0 200 OK\nContent-Type: text/html; charset=utf-8\n\n[showNewFiles]"
    close $chan
}

socket -server serveRequest 8888
vwait forever
