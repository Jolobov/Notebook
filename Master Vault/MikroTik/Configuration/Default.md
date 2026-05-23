#### Configuration
```fold title:"Configuration"
# Set admin password
/user/
set [find name=admin] password="password"

# Set device name
/system/identity/
set name="name"

# Rename WAN interface
/interface/ethernet/
set [ find default-name=ether1 ] name=ether1-WAN1

# Create LAN bridge
/interface/bridge/
add name=bridge

/interface/bridge/port/
add bridge=bridge interface=ether2
add bridge=bridge interface=...
add bridge=bridge interface=wifi1
add bridge=bridge interface=wifi2

# Enable DHCP client on WAN
/ip/dhcp-client/
add disabled=no interface=ether1-WAN1

# Add default route
/ip/route/
add dst-address=0.0.0.0/0 gateway=gateway

# Set DNS servers
/ip/dns/
set servers=77.88.8.8,77.88.8.1



```