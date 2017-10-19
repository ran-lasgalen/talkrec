
proc main {} {
    getOptions - {
	{--sudo-pw "" "password for sudo if it is needed"}
    }
    set ::sudoPassword $::opt(-sudo-pw)
    puts [list ::sudoPassword $::sudoPassword]
}

try {main} on error {err dbg} {debugStackTrace $dbg; puts stderr "\n$err"; exit 2}
