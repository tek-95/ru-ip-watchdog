/# ru-ip-watchdog:pf$/ {next}
  !inserted && /^[[:space:]]*(anchor|block|pass|antispoof)([[:space:]]|$)/ {
    print "table <ru_ip_watchdog> persist file \"/etc/pf.anchors/ru-ip-watchdog-addresses\" " "# ru-ip-watchdog:pf";
    print "block drop out quick from any to <ru_ip_watchdog> " "# ru-ip-watchdog:pf"; inserted=1
  }
  {print}
  END {if(!inserted) {
    print "table <ru_ip_watchdog> persist file \"/etc/pf.anchors/ru-ip-watchdog-addresses\" " "# ru-ip-watchdog:pf";
    print "block drop out quick from any to <ru_ip_watchdog> " "# ru-ip-watchdog:pf"
  }}
