# Installation

    opm install klkvsk/lua-resty-consul-storage-adapter
    
# Configuration

Put this into your `init_by_lua_block`:

    auto_ssl:set("storage_adapter", "resty.consul_storage_adapter")
    
    auto_ssl:set("consul", {
      token = "your-token"
    })
    
Other configurable parameters are:

- `host` (default: 127.0.0.1)
- `port` (default: 8500)
- `connect_timeout` (default: 60s)
- `read_timeout` (default: 60s)   
- `ssl` (default: false)            
- `ssl_verify` (default: true)     
- `sni_host` (default: nil)       

