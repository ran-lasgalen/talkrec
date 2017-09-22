START_TIME=$(date '+%Y%m%d_%H%M%S')

run () {
	if [ -n "$DRY_RUN" ]; then
		echo Would run: "$@"
	else
		echo "$@"
		"$@"
	fi
}

runIn () {
	local D="$1"
	shift
	if [ -z "$D" ]; then echo "Usage: runIn directory command [args...]" >&2; exit 1; fi
	if [ . = "$D" ]; then
		run "$@"
	else
		run pushd "$D" && run "$@" && run popd
	fi
}

throw () {
	echo "$@" >&2
	exit 2
}

INSTALL_STYLE=${INSTALL_STYLE:-working}
[ -d "$HOME" ] || throw '$HOME not defined'
[ -n "$USER" ] || throw '$USER not defined'
[ root != "$USER" ] || throw 'Not suitable for root user'
TALKREC_DIR=$(pwd)
SERVICE_DIR="$HOME/.config/systemd/user"

set_install_style () {
	INSTALL_STYLE=${1:-$INSTALL_STYLE}
	case "$INSTALL_STYLE" in
		working) RUN_STYLE=${RUN_STYLE:-systemd} ;;
		demo) RUN_STYLE=${RUN_STYLE:-screen} ;;
		*) throw "Unknown install style $INSTALL_STYLE" ;;
	esac
	echo "INSTALL_STYLE=$INSTALL_STYLE"
	echo "RUN_STYLE=$RUN_STYLE"
}

install_debs () {
	for deb in "$@"
	do
		dpkg -s $deb 2> /dev/null | grep 'Status:.*installed' > /dev/null || INSTALL_DEBS+=($deb)
	done
	[ -z "${INSTALL_DEBS[*]}" ] || run sudo apt-get install --yes "${INSTALL_DEBS[@]}"
}

fix_example_paths_in () {
	run sed -i -e "s@/home/user/talkrec@$TALKREC_DIR@g" -e "s@/home/user@$HOME@g" "$1"
}

install_systemd_service () {
	local FILE="$1"
	local BASE=$(basename "$FILE" .example)
	run mkdir -p "$SERVICE_DIR"
	run rm -f "$SERVICE_DIR/$BASE.tmp"
	run cp "$FILE" "$SERVICE_DIR/$BASE.tmp"
	fix_example_paths_in "$SERVICE_DIR/$BASE.tmp"
	loginctl show-user "$USER" | grep Linger=yes > /dev/null || run loginctl enable-linger "$USER"
	if cmp "$SERVICE_DIR/$BASE.tmp" "$SERVICE_DIR/$BASE"; then
		run rm -f "$SERVICE_DIR/$BASE.tmp"
	else
		run mv "$SERVICE_DIR/$BASE.tmp" "$SERVICE_DIR/$BASE"
		run systemctl --user daemon-reload
	fi
	run systemctl --user enable "$BASE"
	run systemctl --user stop "$BASE" || true
	run systemctl --user start "$BASE"
	run systemctl --user status "$BASE"
}

