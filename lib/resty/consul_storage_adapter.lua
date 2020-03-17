local resty_consul = require "resty.consul"

local _M = {
  _VERSION = '0.2',
}

local function prefixed_key(self, key)
  if self.options["prefix"] then
    key = self.options["prefix"] .. ":" .. key
  end

  key = string.gsub(key, ":", "/")
  return key
end

local function unprefixed_key(self, key)
  if self.options["prefix"] then
    local offset = string.len(self.options["prefix"]) + 2
    key = string.sub(key, offset)
  end

  key = string.gsub(key, "/", ":")
  return key
end

function _M.new(auto_ssl_instance)
  local options = auto_ssl_instance:get("consul") or {}
  if options["prefix"] == nil then
    options["prefix"] = "resty-auto-ssl"
  end
  return setmetatable({ options = options }, { __index = _M })
end

function _M.setup(self)

end

function _M.get_connection(self)
  if not ngx.ctx.auto_ssl_consul_connection then
    local default_args = self.options["default_args"] or {}
    if self.options["token"] then
      default_args.token = self.options["token"]
    else
      ngx.log(ngx.WARN, "auto-ssl: consul token is not set")
      default_args.token = ""
    end
  
    ngx.ctx.auto_ssl_consul_connection = resty_consul:new({
      host              = self.options["host"],
      port              = self.options["port"],
      default_args      = default_args,
      connect_timeout   = self.options["connect_timeout"],
      read_timeout      = self.options["read_timeout"],
      ssl               = self.options["ssl"],
      ssl_verify        = self.options["ssl_verify"],
      sni_host          = self.options["sni_host"]
    })
  end

  return ngx.ctx.auto_ssl_consul_connection
end

function _M.get(self, key)
  local consul = self:get_connection()

  local res, err = consul:get_key(prefixed_key(self, key))
  if err then
    ngx.log(ngx.ERR, "auto-ssl: failed to get key '" .. key .. "' from consul: ", err)
    return nil, err
  end

  if res.status ~= 200 and res.status ~= 404 then
    ngx.log(ngx.ERR, "auto-ssl: got HTTP code " .. res.status .. " from consul in get('" .. key .. "')")
    return nil, "consul response is " .. res.status
  end

  if res.status == 404 then
    return nil
  else
    return res.body[1].Value;
  end
end

function _M.set(self, key, value, options)
  local consul = self:get_connection()

  local res, err = consul:put_key(prefixed_key(self, key), value)
  if err then
    ngx.log(ngx.ERR, "auto-ssl: failed to put key '" .. key .. "' to consul: ", err)
    return false, err
  end

  if res.status ~= 200 then
    ngx.log(ngx.ERR, "auto-ssl: got HTTP code " .. res.status .. " from consul in set('" .. key .. "')")
    return nil, "consul response is " .. res.status
  end

  if options and options["exptime"] then
    ngx.timer.at(options["exptime"], function()
      local _, err = _M.delete(self, key)
      if err then
        ngx.log(ngx.ERR, "auto-ssl: failed to delete key '" .. key .. " after exptime: ", err)
      end
    end)
  end

  return true
end

function _M.delete(self, key)
  local consul = self:get_connection()

  local res, err = consul:delete_key(prefixed_key(self, key))
  if err then
    ngx.log(ngx.ERR, "auto-ssl: failed to delete key '" .. key .. "' from consul: ", err)
    return false, err
  end

  if res.status ~= 200 then
    ngx.log(ngx.ERR, "auto-ssl: got HTTP code " .. res.status .. " from consul in delete('" .. key .. "')")
    return true -- still okay
  end

  return true
end

function _M.keys_with_suffix(self, suffix)
  local consul = self:get_connection()

  local res, err = consul:list_keys(prefixed_key(self, ""))
  if err then
    ngx.log(ngx.ERR, "auto-ssl: failed to get keys from consul: ", err)
    return {}, err
  end

  if res.status ~= 200 then
    ngx.log(ngx.ERR, "auto-ssl: got HTTP code " .. res.status .. " from consul in keys_with_suffix('" .. suffix .. "')")
    return nil, "consul response is " .. res.status
  end

  local keys = {}

  for _, key in ipairs(res.body) do
    local clean_key = unprefixed_key(self, key)
    if suffix == "" or clean_key:sub(-#suffix) == suffix then
      table.insert(keys, clean_key)
    end
  end

  return keys
end

return _M

