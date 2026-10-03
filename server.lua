-- Tiny non-blocking HTTP responder for the companion page. Every socket runs
-- with a zero timeout and is pumped from core.update, so a slow or vanished
-- phone can never stall a frame: it just gets dropped after IDLE_SECONDS.
return function(mod, socket)
    local MAX_ACCEPT = 4 -- new connections taken per frame
    local MAX_CLIENTS = 8
    local MAX_REQUEST = 8192 -- bytes of request line + headers
    local IDLE_SECONDS = 5

    local MAX_BODY = 4096 -- POST bodies are small JSON commands

    local REASONS = {
        [200] = "OK",
        [400] = "Bad Request",
        [403] = "Forbidden",
        [404] = "Not Found",
        [405] = "Method Not Allowed",
        [409] = "Conflict",
        [413] = "Payload Too Large",
        [429] = "Too Many Requests",
        [500] = "Internal Server Error"
    }
    local METHODS = { GET = true, HEAD = true, POST = true }

    local Server = {}
    Server.__index = Server

    -- IPv4 on purpose: bind("*") on a family-less socket resolves to "::"
    -- first, which Windows makes IPv6-only, so a phone dialing the PC's IPv4
    -- LAN address would be refused.
    -- socket.bind() always sets SO_REUSEADDR, which on Windows lets a second
    -- game instance bind the same port and silently share connections.
    -- Elsewhere it is still wanted so a restart is not blocked by TIME_WAIT.
    local function listen(port)
        local sock, err = (socket.tcp4 or socket.tcp)()
        if not sock then return nil, err end
        if jit.os ~= "Windows" then sock:setoption("reuseaddr", true) end
        local ok
        ok, err = sock:bind("0.0.0.0", port)
        if ok then ok, err = sock:listen(16) end
        if not ok then
            sock:close()
            return nil, err
        end
        sock:settimeout(0)
        return sock
    end

    -- handler(req) -> status, contentType, body[, maxAge]
    -- req = { method, path, query, headers (lowercase names), body }
    -- maxAge (seconds) lets the browser cache the response; default no-store
    -- Quitting a game to the launcher drops this mod instance without telling
    -- it (no event fires), so its listener would hold the port until the
    -- garbage collector found it and the next game's companion couldn't bind.
    -- The running server is noted on the luasocket module, which stays loaded
    -- for the whole run, and a new one closes the one before it first.
    local HOLDER = "__second_screen_companion_server"

    function Server.new(port, handler)
        local previous = rawget(socket, HOLDER)
        if previous then
            pcall(previous.stop, previous)
        end
        local sock, err = listen(port)
        if not sock then return nil, err end
        local self = setmetatable({ port = port, sock = sock, handler = handler, clients = {} }, Server)
        rawset(socket, HOLDER, self)
        return self
    end

    local function response(method, status, contentType, body, maxAge)
        body = body or ""
        local cache = maxAge and ("public, max-age=%d, immutable"):format(maxAge) or "no-store"
        local head = ("HTTP/1.1 %d %s\r\n"
            .. "Content-Type: %s\r\n"
            .. "Content-Length: %d\r\n"
            .. "Cache-Control: %s\r\n"
            .. "X-Content-Type-Options: nosniff\r\n"
            .. "Connection: close\r\n\r\n"):format(status, REASONS[status] or "OK", contentType, #body, cache)
        if method == "HEAD" then return head end
        return head .. body
    end

    function Server:_respond(c)
        local method, target = c.requestLine:match("^(%u+)%s+(%S+)")
        if not METHODS[method] then
            return response(method, 405, "text/plain", "GET or POST only\n")
        end
        local req = {
            method = method,
            path = target:match("^[^?#]*"),
            query = target:match("%?([^#]*)") or "",
            headers = c.headers,
            body = c.body or ""
        }
        local ok, status, contentType, body, maxAge = pcall(self.handler, req)
        if not ok then
            mod.log:error("request %s failed: %s", tostring(target), tostring(status))
            return response(method, 500, "text/plain", "internal error\n")
        end
        return response(method, status, contentType, body, maxAge)
    end

    -- Reads the request line and headers, then Content-Length bytes of body.
    -- Returns true once the client should be closed.
    function Server:_read(c)
        while not c.bodyLength do
            local line, err, partial = c.sock:receive("*l", c.partial)
            if not line then
                if err ~= "timeout" then return true end
                c.partial = partial
                return #partial > MAX_REQUEST
            end
            c.partial = nil
            c.size = c.size + #line
            if c.size > MAX_REQUEST then return true end
            if not c.requestLine then
                c.requestLine = line
                c.headers = {}
            elseif line == "" then
                local length = tonumber(c.headers["content-length"] or "0") or -1
                if length < 0 or length > MAX_BODY then
                    c.out, c.sent = response("POST", 413, "text/plain", "body too large\n"), 0
                    return false
                end
                c.bodyLength = length
            else
                local name, value = line:match("^([^:]+):%s*(.-)%s*$")
                if name then c.headers[name:lower()] = value end
            end
        end
        if c.bodyLength > 0 then
            local chunk, err, partial = c.sock:receive(c.bodyLength, c.partial)
            if not chunk then
                if err ~= "timeout" then return true end
                c.partial = partial
                return false
            end
            c.body = chunk
        end
        c.partial = nil
        c.out, c.sent = self:_respond(c), 0
        return false
    end

    function Server:_write(c)
        local last, err, partialLast = c.sock:send(c.out, c.sent + 1)
        if last then return true end
        if err ~= "timeout" then return true end
        c.sent = partialLast or c.sent
        return false
    end

    function Server:poll(dt)
        local clients = self.clients
        for _ = 1, MAX_ACCEPT do
            if #clients >= MAX_CLIENTS then break end
            local sock = self.sock:accept()
            if not sock then break end
            sock:settimeout(0)
            clients[#clients + 1] = { sock = sock, age = 0, size = 0 }
        end
        for i = #clients, 1, -1 do
            local c = clients[i]
            c.age = c.age + dt
            local done = c.age > IDLE_SECONDS
            if not done and not c.out then done = self:_read(c) end
            if not done and c.out then done = self:_write(c) end
            if done then
                c.sock:close()
                table.remove(clients, i)
            end
        end
    end

    function Server:stop()
        for _, c in ipairs(self.clients) do c.sock:close() end
        self.clients = {}
        self.sock:close()
        if rawget(socket, HOLDER) == self then rawset(socket, HOLDER, nil) end
    end

    return Server
end
