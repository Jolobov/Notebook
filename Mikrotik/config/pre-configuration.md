```
# Update RouterOS
/system/package/update/
set channel=long-term

/system/package/update/
check-for-updates
install

# Update RouterBOOT
/system/routerboard/
upgrade

/system/
reboot

# Reset configuration
/system/
reset-configuration no-defaults=yes skip-backup=yes
```