---@meta mongodb
--- LuaCATS annotations for the `mongodb` Prova plugin — the consumer-facing contract for
--- `local mongodb = require("mongodb")`. prova syncs this into a project's `annotations/` so
--- `require("mongodb")` resolves by module name. Keep in step with `../mongodb.lua`.

---A docker-exec MongoDB client (drives the `mongosh` CLI inside the container). Documents and queries
---are plain Lua tables — encoded to JSON on the way in, EJSON-parsed on the way out (so an ObjectId
---reads as `{ ["$oid"] = "..." }`).
---@class mongodb.Client
local Client = {}

---Evaluate arbitrary JS against the database and return trimmed stdout — the generic escape hatch.
---@param js string
---@return string
function Client:eval(js) end

---Ping the server; returns "1" when it is up.
---@return string
function Client:ping() end

---Insert one document; returns its `_id` (EJSON-parsed).
---@param coll string
---@param doc table
---@return any id
function Client:insert_one(coll, doc) end

---Insert many documents; returns the inserted `_id`s in order.
---@param coll string
---@param docs table[]
---@return any[] ids
function Client:insert_many(coll, docs) end

---Find documents matching `query` (default all); returns a list of documents.
---@param coll string
---@param query table?
---@return table[] docs
function Client:find(coll, query) end

---Find the first document matching `query` (default all), or nil.
---@param coll string
---@param query table?
---@return table? doc
function Client:find_one(coll, query) end

---Count documents matching `query` (default all).
---@param coll string
---@param query table?
---@return integer
function Client:count(coll, query) end

---Delete documents matching `query` (default all); returns the deleted count.
---@param coll string
---@param query table?
---@return integer deleted
function Client:delete_many(coll, query) end

---Drop a collection; returns true if it existed.
---@param coll string
---@return boolean
function Client:drop(coll) end

---No-op; the container teardown reaps everything.
function Client:close() end

---The provisioned MongoDB: `{ client, url, container }`.
---@class mongodb.Resource
---@field client mongodb.Client the client to drive collections against
---@field url string the `mongodb://…` endpoint for the app under test
---@field container prova.Container the raw container (host_port, logs, run, exec, stop)

---@class mongodb
local mongodb = {}

---Provision an ephemeral MongoDB, gate on a `ping` that holds, and return the resource. Teardown is
---tied to `ctx`.
---@param ctx prova.Context
---@param opts { database?: string, image?: string, tag?: string }?
---@return mongodb.Resource
function mongodb.container(ctx, opts) end

return mongodb
