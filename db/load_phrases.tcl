package require tdbc
package require tdbc::postgres
package require yaml

set phrases [::yaml::yaml2dict -file phrases.yaml]
set translated {}

::tdbc::postgres::connection create db -database talkrec
db transaction {
    foreach cat [dict keys $phrases] {
	set catId [db allrows -as lists {select id from phrase_category where title = :cat}]
	puts "$cat $catId"
	foreach k {да нет} {
	    if {$k eq "да"} {set desired 1} {set desired 0}
	    foreach phrase [dict get $phrases $cat $k] {
		set description [regsub -all {\s+} [string tolower $phrase] " "]
		set re0 [regsub -all {[[:punct:][:space:]]+} $description {[., ]+}]
		set re1 "\\m$re0\\M"
		if {[dict exists $translated $description]} {
		    error "Duplicate $description:\n  [dict get $translated $description]\n  [list $re1 $desired $catId]"
		} else {
		    dict set translated $description [list $re1 $desired $catId]
		}
	    }
	}
    }
    foreach description [dict keys $translated] {
	set re [lindex [dict get $translated $description] 0]
	foreach otherDesc [dict keys $translated] {
	    if {$otherDesc eq $description} continue
	    if {[regexp $re $otherDesc]} {
		error "$description is a sub of $otherDesc"
	    }
	}
    }
    dict for {description rest} $translated {
	foreach {regexp desired catId} $rest break
	db allrows -as lists {insert into phrase (description, regexp, desired, category_id) values (:description, :regexp, :desired, :catId)}
    }
}
db close
