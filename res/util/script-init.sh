#!/system/bin/sh
# MinMicroG bootup script

# Wait for bootup
while true; do [ "$(getprop sys.boot_completed)" = "1" ] && break; sleep 5; done;

# First-boot migration after flashing over an existing setup (dirty flash, beta)
# The installer writes the list of affected packages here; must match
# migrate_file in the defconfs
migrate_file="/data/.mmg-migrate";
migrate_log="/data/.mmg-migrate.log";

if [ -f "$migrate_file" ]; then
  {
    echo "MinMicroG migration started $(date)";
    users="$(pm list users | sed -n 's/.*UserInfo{\([0-9]*\):.*/\1/p')";
    [ -n "$users" ] || users="0";
    while read -r pkg; do
      [ -n "$pkg" ] || continue;
      if ! pm list packages | grep -qx "package:$pkg"; then
        echo "$pkg: not installed, skipping";
        continue;
      fi;
      # Drop user-installed updates of system packages (e.g. Play Services
      # self-updates) so the system copy installed by MinMicroG is in use.
      # Only for system packages: on a user-only app, uninstall removes it.
      if pm list packages -s | grep -qx "package:$pkg"; then
        case "$(pm path "$pkg")" in
          *package:/data/*)
            echo "$pkg: removing installed update: $(pm uninstall "$pkg" 2>&1)";
          ;;
        esac;
      fi;
      # Reset data and runtime permission state of the leftover package
      for user in $users; do
        echo "$pkg: clearing data for user $user: $(pm clear --user "$user" "$pkg" 2>&1)";
      done;
    done < "$migrate_file";
    echo "MinMicroG migration finished $(date)";
  } >> "$migrate_log" 2>&1;
  rm -f "$migrate_file";
fi;

# Grant permissions
npem;
