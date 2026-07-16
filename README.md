# prova-mongodb

A database resource plugin for [Prova](https://github.com/prova-rs/prova) — MongoDB — docker-exec over the mongosh CLI, zero native code.

A **docker-exec** plugin: zero native code. It provisions an ephemeral `mongo` container, waits
for readiness, and drives the CLI already in the image (`mongosh`) — all through Prova's
`prova.containerized` + `container:run` SDK. Documents and queries are plain Lua tables (encoded to
JSON on the way in, EJSON-parsed on the way out).

## Use it

Declare the plugin in your `prova.toml`:

```toml
[plugins]
mongodb = "prova-rs/prova-mongodb@v1"   # org/repo shorthand (fetched, pinned, cached)
```

Then in a test:

```lua
local mongodb = require("mongodb")

local db = prova.fixture("mongodb", Scope.File, function(ctx)
  return mongodb.container(ctx, { database = "orders" })   -- provisions, waits, attaches a client
end)

prova.group("example", { requires = { "docker" } }, function(g)
  g:test("stores and reads a document", function(t)
    local c = t:use(db).client
    c:insert_one("items", { _id = 1, name = "alpha" })
    t:expect(c:count("items")):equals(1)
    t:expect(c:find_one("items", { _id = 1 }).name):equals("alpha")
  end)
end)
```

Hand `r.url` (a `mongodb://…` endpoint) to the app under test via its env, and assert the effect
either through the app's API (black-box) or directly with the client here.

## API

`mongodb.container(ctx, opts?)` → `{ client, url, container }`

- `url` — `mongodb://127.0.0.1:<port>/<database>`, the endpoint for the app under test.
- `container` — the Docker handle (`:host_port`, `:run`, `:logs`, …).
- `client` — the docker-exec client:
  - `insert_one(coll, doc)` / `insert_many(coll, docs)` — insert; return the inserted `_id`(s).
  - `find(coll, query?)` / `find_one(coll, query?)` — read documents (query defaults to match-all).
  - `count(coll, query?)` — count documents.
  - `delete_many(coll, query?)` — delete; returns the deleted count.
  - `drop(coll)` — drop a collection.
  - `eval(js)` — evaluate arbitrary JS (escape hatch).

`opts`: `database` (default `prova`), plus `image`, `tag` (default `7`), `timeout` — the
`prova.containerized` options.

## Requirements

Docker at test time. Gate tests with `requires = { "docker" }` so they skip cleanly where the daemon
is absent.

## Develop

```bash
prova                          # runs tests/ against ./mongodb.lua (needs Docker)
prova plugin lint mongodb.lua
```

MIT licensed.
