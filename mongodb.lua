-- prova-mongodb — a MongoDB plugin via docker-exec over the `mongosh` CLI (zero native code).
-- Provisions an ephemeral mongo:7 container and drives it with the CLI already in the image, through
-- Prova's prova.containerized + container:run SDK. mongosh exits non-zero until the server answers,
-- so a `ping` in the client factory is the readiness gate (prova.retry loops until it holds).
--
--   local mongodb = require("mongodb")
--   local db = mongodb.container(ctx, { database = "orders" })   -- { client, url, container }
--   db.client:insert_one("items", { _id = 1, name = "alpha" })
--   db.client:count("items")                                     -- 1
--   db.client:find("items", { name = "alpha" })                  -- { { _id = 1, name = "alpha" } }

-- Escape a string as a JSON string literal (control chars → \uXXXX). Used by encode() below.
local JSON_ESC = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r',
  ['\t'] = '\\t', ['\b'] = '\\b', ['\f'] = '\\f',
}
local function encode_string(s)
  return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
    return JSON_ESC[c] or string.format("\\u%04x", string.byte(c))
  end) .. '"'
end

-- A table is treated as a JSON array iff its keys are exactly 1..n (n >= 1); anything else (including
-- the empty table) is an object. Callers that need a literal empty array/object pass the JS directly.
local function array_length(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k % 1 ~= 0 or k < 1 then return nil end
    if k > n then n = k end
  end
  if n == 0 then return nil end
  for i = 1, n do if t[i] == nil then return nil end end
  return n
end

-- Encode a Lua value to JSON (a valid mongosh/EJSON expression). Strings are quoted, numbers/bools
-- verbatim, nil → null. This is what makes the client accept Lua tables for documents and queries.
local function encode(v)
  local tv = type(v)
  if v == nil then return "null"
  elseif tv == "number" then return tostring(v)
  elseif tv == "boolean" then return v and "true" or "false"
  elseif tv == "string" then return encode_string(v)
  elseif tv == "table" then
    local n = array_length(v)
    if n then
      local parts = {}
      for i = 1, n do parts[i] = encode(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local parts = {}
    for k, val in pairs(v) do
      parts[#parts + 1] = encode_string(tostring(k)) .. ":" .. encode(val)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("mongodb: cannot encode a value of type " .. tv)
end

local function make_client(container, conn)
  -- Run one JS statement via the mongosh CLI inside the container. `--quiet` drops the banner so
  -- stdout is just the eval result; argv form means no shell, no quoting. Trims the trailing newline.
  -- Raises on non-zero exit (checked-exec) — a dropped connection surfaces as an error.
  local function sh(js)
    return (container:run({ "mongosh", conn.uri, "--quiet", "--eval", js }):gsub("%s+$", ""))
  end

  -- A collection query defaults to `{}` (match all) — an empty Lua table would encode as an object
  -- too, but spelling the default here keeps `find(coll)` explicit and avoids the ambiguity.
  local function q(query)
    return query and encode(query) or "{}"
  end

  local client = {}

  -- Evaluate arbitrary JS and return trimmed stdout — the generic escape hatch.
  function client:eval(js) return sh(js) end

  -- `db.runCommand({ ping: 1 }).ok` → "1" when the server is up.
  function client:ping() return sh("db.runCommand({ ping: 1 }).ok") end

  -- Insert one document; returns its `_id` (parsed from EJSON, so an ObjectId reads as
  -- `{ ["$oid"] = "..." }` and an explicit scalar `_id` reads as that scalar).
  function client:insert_one(coll, doc)
    return prova.parse.json(sh(string.format(
      "EJSON.stringify(db.getCollection(%s).insertOne(%s).insertedId)",
      encode(coll), encode(doc))))
  end

  -- Insert many documents; returns the list of inserted `_id`s in order.
  function client:insert_many(coll, docs)
    return prova.parse.json(sh(string.format(
      "EJSON.stringify(Object.values(db.getCollection(%s).insertMany(%s).insertedIds))",
      encode(coll), encode(docs))))
  end

  -- Find documents matching `query` (default all); returns a list of documents (parsed EJSON).
  function client:find(coll, query)
    return prova.parse.json(sh(string.format(
      "EJSON.stringify(db.getCollection(%s).find(%s).toArray())", encode(coll), q(query))))
  end

  -- Find the first matching document, or nil.
  function client:find_one(coll, query)
    return prova.parse.json(sh(string.format(
      "EJSON.stringify(db.getCollection(%s).findOne(%s))", encode(coll), q(query))))
  end

  -- Count documents matching `query` (default all).
  function client:count(coll, query)
    return tonumber(sh(string.format(
      "db.getCollection(%s).countDocuments(%s)", encode(coll), q(query))))
  end

  -- Delete documents matching `query` (default all); returns the deleted count.
  function client:delete_many(coll, query)
    return tonumber(sh(string.format(
      "db.getCollection(%s).deleteMany(%s).deletedCount", encode(coll), q(query))))
  end

  -- Drop a collection; returns true if it existed.
  function client:drop(coll)
    return sh(string.format("db.getCollection(%s).drop()", encode(coll))) == "true"
  end

  function client:close() end
  return client
end

local mongodb = prova.containerized{
  name = "mongodb", image = "mongo", tag = "7", port = 27017, timeout = "60s",
  url = function(hp, opts)
    return string.format("mongodb://127.0.0.1:%d/%s", hp, opts.database or "prova")
  end,
  -- The factory execs into the container; `ping` is the readiness gate (mongosh raises until the
  -- server answers, so container:run raises and prova.retry loops until it's up).
  client = function(_url, opts, container)
    local database = opts.database or "prova"
    local conn = { database = database, uri = "mongodb://127.0.0.1:27017/" .. database }
    local client = make_client(container, conn)
    if client:ping() ~= "1" then error("mongodb did not answer ping") end
    return client
  end,
}

return mongodb
