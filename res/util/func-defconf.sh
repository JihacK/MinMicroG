# Functions for use by defconfs

# Process user confs
user_conf() {

  for file in "$(dirname "$0")/mmg-conf.txt" "$(dirname "$zipfile")/mmg-conf.txt" "$moddir/mmg-conf.txt" "/data/adb/mmg-conf.txt"; do
    [ -f "$file" ] && {
      ui_print " "; ui_print "Processing user config $file...";
      includelist="$(sed -e 's|\#.*||g' -e 's|[^a-zA-Z0-9._-]| |g' "$file")";
      break;
    }
  done;
  # Words starting with "opt-" are install options, not package filters
  mmg_options="";
  filterlist="";
  for word in $includelist; do
    case "$word" in
      opt-*)
        log "Enabling option $word";
        mmg_options="$mmg_options $word";
      ;;
      *)
        filterlist="$filterlist $word";
      ;;
    esac;
  done;
  includelist="$filterlist";
  [ "$includelist" ] && {
    new_stuff="";
    new_stuff_arch="";
    new_stuff_sdk="";
    new_stuff_arch_sdk="";
    for include in $includelist; do
      log "Including keyword $include";
      new_stuff="$new_stuff $(echo "$stuff" | grep -oi "[ ]*[^ ]*$include[^ ]*[ ]*")";
      new_stuff_arch="$new_stuff_arch $(echo "$stuff_arch" | grep -oi "[ ]*[^ ]*$include[^ ]*[ ]*")";
      new_stuff_sdk="$new_stuff_sdk $(echo "$stuff_sdk" | grep -oi "[ ]*[^ ]*$include[^ ]*[ ]*")";
      new_stuff_arch_sdk="$new_stuff_arch_sdk $(echo "$stuff_arch_sdk" | grep -oi "[ ]*[^ ]*$include[^ ]*[ ]*")";
    done;
    stuff="$new_stuff";
    stuff_arch="$new_stuff_arch";
    stuff_sdk="$new_stuff_sdk";
    stuff_arch_sdk="$new_stuff_arch_sdk";
  }
  [ "$includelist" ] && {
    stuff="$(echo "$stuff" | sed 's| |\n|g' | sort -u | sed 's|^|  |g')
";
    stuff_arch="$(echo "$stuff_arch" | sed 's| |\n|g' | sort -u | sed 's|^|  |g')
";
    stuff_sdk="$(echo "$stuff_sdk" | sed 's| |\n|g' | sort -u | sed 's|^|  |g')
";
    stuff_arch_sdk="$(echo "$stuff_arch_sdk" | sed 's| |\n|g' | sort -u | sed 's|^|  |g')
";
  }

  [ "$stuff" ] || [ "$stuff_arch" ] || [ "$stuff_sdk" ] || [ "$stuff_arch_sdk" ] || abort "Nothing left to install after config";

}

# Check whether an "opt-" option was enabled in mmg-conf.txt
mmg_option() {

  case " $mmg_options " in
    *" $1 "*) return 0; ;;
  esac;
  return 1;

}

# Prepare for microG, and queue a first-boot migration if a previous
# GApps or microG setup left data behind (dirty flash, beta)
microg_cleanup() {

  echo "$stuff" | grep -q "MicroG" || return 0;

  ui_print " ";
  ui_print "Doing MicroG preparations...";

  # Kanged from NanoDroid
  # Thanks Setialpha
  cleanup_folders="BlankStore GmsCore GmsCore_update GmsCoreSetupPrebuilt GoogleServicesFramework GsfProxy Phonesky PlayStore PrebuiltGmsCorePi PrebuiltGmsCorePix PrebuiltGmsCore Vending";
  cleanup_packages="com.android.vending com.google.android.feedback com.google.android.gms com.google.android.gsf com.google.android.gsf.login com.mgoogle.android.gms";

  # Stale compiled code of replaced system apps (only safe while not booted)
  if [ "$bootmode" != "true" ]; then
    for app in $cleanup_folders; do
      for file in /data/dalvik-cache/*/system"@priv-app@$app"[@\.]*@classes.* /data/dalvik-cache/*/system"@app@$app"[@\.]*@classes.*; do
        [ -e "$file" ] && { log "PREPPER: Removing $file"; rm -rf "$file"; }
      done;
    done;
  fi;

  if [ -f "$mark_file" ]; then
    log "PREPPER: This is an update flash";
    return 0;
  fi;

  # Packages that still have data from a previous setup
  migrate_list="";
  for app in $cleanup_packages; do
    for dir in "/data/data/$app" /data/user/*/"$app" /data/user_de/*/"$app"; do
      [ -e "$dir" ] && { migrate_list="$migrate_list $app"; break; }
    done;
  done;

  if [ -z "$migrate_list" ]; then
    log "PREPPER: Clean install, nothing to migrate";
    return 0;
  fi;

  if mmg_option opt-nomigrate; then
    ui_print "Existing setup found, but migration disabled (opt-nomigrate)";
    return 0;
  fi;

  ui_print "Existing setup found (dirty flash, beta)";
  ui_print " ";
  ui_print "WARNING: Dirty flash support is UNTESTED on real devices.";
  ui_print "Keep a backup. Use opt-nomigrate in mmg-conf.txt to skip it.";
  ui_print " ";
  ui_print "These apps will be reset on first boot:";
  for app in $migrate_list; do
    ui_print " - $app";
  done;
  rm -f "$migrate_file";
  for app in $migrate_list; do
    echo "$app" >> "$migrate_file";
  done;
  log "PREPPER: Wrote migration list to $migrate_file";

  if mmg_option opt-wipeaccounts; then
    if [ "$bootmode" = "true" ]; then
      ui_print "opt-wipeaccounts only works when flashing from recovery";
    elif command -v "sqlite3" >/dev/null; then
      find /data/system* -type f -name "accounts*db" 2>/dev/null | while read -r database; do
        log "PREPPER: deleting Google Accounts from $database";
        sqlite3 "$database" "DELETE FROM accounts WHERE type='com.google';";
      done;
    else
      ui_print "opt-wipeaccounts: sqlite3 not found, accounts kept";
    fi;
  fi;

}

# Generate and install an addon.d script
addon_install() {

  [ "$magisk" = "no" ] || return 0;
  [ "$addond_file" ] && [ -e "$filedir/util/script-addon.sh" ] || return 1;

  log " ";
  log "POST-INSTALL: Installing addon.d script";

  addond="$addond_file";
  mkdir -p "$(dirname "$root/$addond")";
  touch "$root/$addond";
  perm 0 0 0755 0644 "$(dirname "$root/$addond")";
  chcon -hR 'u:object_r:system_file:s0' "$(dirname "$root/$addond")";

  cat "$filedir/util/script-addon.sh" > "$root/$addond";
  echo "$stuff" "$stuff_arch" "$stuff_sdk" "$stuff_arch_sdk" "$addond_file" "$init_file" | sed 's| |\n|g' | sort -u > "$filedir/util/INSTALLLIST";
  echo "$stuff_debloat" | sed 's| |\n|g' | sort -u > "$filedir/util/DEBLOATLIST";
  sed -i -e "/@INSTALLLIST@/r $filedir/util/INSTALLLIST" -e "/@INSTALLLIST@/d" "$root/$addond";
  sed -i -e "/@DEBLOATLIST@/r $filedir/util/DEBLOATLIST" -e "/@DEBLOATLIST@/d" "$root/$addond";

}

# Place an init script
initscript_install() {

  [ "$init_file" ] && [ -e "$filedir/util/script-init.sh" ] || return 1;

  log " ";
  log "POST-INSTALL: Installing init script";

  if [ "$magisk" = "yes" ]; then
    init="/service.sh";
    touch "$root/$init";
    chmod 0777 "$root/$init";
  elif [ "$magisk" = "no" ]; then
    init="$init_file";
    mkdir -p "$(dirname "$root/$init")";
    touch "$root/$init";
    perm 0 0 0755 0777 "$(dirname "$root/$init")";
    chcon -hR 'u:object_r:system_file:s0' "$(dirname "$root/$init")";
  fi;

  cat "$filedir/util/script-init.sh" > "$root/$init";

}
