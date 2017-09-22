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

[ -d "$HOME" ] || throw '$HOME not defined'
[ -n "$USER" ] || throw '$USER not defined'
[ root != "$USER" ] || throw 'Not suitable for root user'
TALKREC_DIR=$(pwd)
SERVICE_DIR="$HOME/.config/systemd/user"

install_systemd_service () {
	local FILE="$1"
	local BASE=$(basename "$FILE" .example)
	run mkdir -p "$SERVICE_DIR"
	run rm -f "$SERVICE_DIR/$BASE.tmp"
	run cp "$FILE" "$SERVICE_DIR/$BASE.tmp"
	run sed -i -e "s!/home/user/talkrec!$TALKREC_DIR!g" -e "s!/home/user!$HOME!g" "$SERVICE_DIR/$BASE.tmp"
	loginctl show-user "$USER" | grep Linger=yes > /dev/null || run loginctl enable-linger "$USER"
	if cmp "$SERVICE_DIR/$BASE.tmp" "$SERVICE_DIR/$BASE"; then
		run rm -f "$SERVICE_DIR/$BASE.tmp"
	else
		run mv "$SERVICE_DIR/$BASE.tmp" "$SERVICE_DIR/$BASE"
		run systemctl --user daemon-reload
	fi
	run systemctl --user enable dispatcher
	run systemctl --user start dispatcher
	run systemctl --user status dispatcher
}
