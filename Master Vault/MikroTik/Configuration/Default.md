#### Configuration
```fold title:"Configuration"
# Set admin password
/user/
set [find name=admin] password="new_password"

# Set device name
/system/identity/
set name="name"

# Rename WAN interface
/interface/ethernet/
set [ find default-name=ether1 ] name=ether1-WAN1

# Create LAN bridge
/interface/bridge/
add name=bridge-LAN

/interface/bridge/port/
add bridge=bridge-LAN interface=ether2
add bridge=bridge-LAN interface=...
add bridge=bridge-LAN interface=wifi1
add bridge=bridge-LAN interface=wifi2

# Enable DHCP client on WAN
/ip/dhcp-client/
add disabled=no interface=ether1-WAN1

# Add default route
/ip/route/
add dst-address=0.0.0.0/0 gateway=gateway

# Set DNS servers
/ip/dns/
set servers=77.88.8.8,77.88.8.1



# Configure Input chain firewall rules
/ip/firewall/filter/
add action=accept chain=input \
   connection-state=established,related \
   comment="root: accept established related"
add action=drop chain=input
   connection-state=invalid \
   comment="root: drop invalid"
add action=accept chain=input \
   protocol=icmp \
   comment="root: accept ICMP" 
add action=drop chain=input \
   in-interface=!bridge-LAN \
   comment="root: drop all from not LAN"

# Configure Forward chain firewall rules
/ip/firewall/filter/
add action=accept chain=forward \
   connection-state=established,related \
   comment="accept established & related"
add action=drop chain=forward \
   connection-state=invalid \
   comment="drop invalid"
add action=drop chain=forward \
   connection-nat-state=!dstnat \
   in-interface=ether1-WAN1 \
   comment="drop all from WAN"

# Configure Layer 2 security
/interface/list/
add name=LAN

/interface/list/member/
add interface=bridge-LAN list=LAN

/ip/neighbor/discovery-settings/
set discover-interface-list=LAN

/tool/mac-server/
set allowed-interface-list=LAN

/tool/mac-server/mac-winbox/
set allowed-interface-list=LAN

/tool/mac-server/ping/
set enabled=no

# Disable IPv6
/ipv6/settings/
set disable-ipv6=yes

# Disable unused services
/ip/service/
set api disabled=yes
set api-ssl disabled=yes
set telnet disabled=yes
set ftp disabled=yes
set www disabled=yes

# Configure NTP client
/system/ntp/client/
set enabled=yes

/system/ntp/client/servers/
add address=ru.pool.ntp.org

/system/clock/
set time-zone-autodetect=no time-zone-name=Europe/Moscow

# Reboot system
/system/
reboot
```