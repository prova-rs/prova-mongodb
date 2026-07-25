-- The prova-mongodb proof suite: every exported client verb (insert_one/insert_many/find/
-- find_one/count/delete_many/drop/eval/ping), EJSON id round-trips, miss semantics, and the
-- string-encoding fidelity of the hand-rolled Lua→JSON encoder — all against a real mongo:7
-- container. Requires docker; skips otherwise.

local db = prova.fixture("mongodb", Scope.File, function(ctx)
  return require("mongodb").container(ctx, { database = "orders" })
end)

prova.group("mongodb", { requires = { "docker" } }, function(g)
  g:test("insert + count + find + delete round-trip", function(t)
    local c = t:use(db).client
    c:drop("items")

    c:insert_many("items", {
      { _id = 1, name = "alpha", qty = 3 },
      { _id = 2, name = "beta", qty = 7 },
    })

    t:expect(c:count("items")):equals(2)
    t:expect(c:count("items", { name = "alpha" })):equals(1)
    t:expect(c:count("items", { name = "nope" })):equals(0)

    local doc = c:find_one("items", { _id = 1 })
    t:expect(doc.name):equals("alpha")
    t:expect(doc.qty):equals(3)

    local rows = c:find("items")
    t:expect(#rows):equals(2)

    t:expect(c:delete_many("items", { name = "beta" })):equals(1)
    t:expect(c:count("items")):equals(1)
    c:drop("items")
  end)

  g:test("insert_one returns the id: an explicit scalar as itself, a generated one as $oid",
    function(t)
    local c = t:use(db).client
    c:drop("ids")
    t:expect(c:insert_one("ids", { _id = 42, kind = "explicit" })):equals(42)
    local generated = c:insert_one("ids", { kind = "generated" })
    t:expect(type(generated)):equals("table")
    t:expect(generated["$oid"]):matches("^%x+$")   -- EJSON ObjectId envelope
    c:drop("ids")
  end)

  g:test("insert_many returns the inserted ids in order", function(t)
    local c = t:use(db).client
    c:drop("ordered")
    local ids = c:insert_many("ordered", { { _id = "a" }, { _id = "b" }, { _id = "c" } })
    t:expect(ids):equals({ "a", "b", "c" })
    c:drop("ordered")
  end)

  g:test("find_one misses as nil; delete_many with no query clears the collection", function(t)
    local c = t:use(db).client
    c:drop("misses")
    t:expect(c:find_one("misses", { _id = 999 })):is_falsy()
    c:insert_many("misses", { { _id = 1 }, { _id = 2 }, { _id = 3 } })
    t:expect(c:delete_many("misses")):equals(3)
    t:expect(c:count("misses")):equals(0)
  end)

  g:test("drop reports whether the collection existed", function(t)
    local c = t:use(db).client
    c:insert_one("droppable", { _id = 1 })
    t:expect(c:drop("droppable")):is_true()
    t:expect(c:drop("droppable")):is_falsy()   -- second drop: nothing to drop
  end)

  g:test("string values survive quotes, newlines, and unicode through the encoder", function(t)
    local c = t:use(db).client
    c:drop("fidelity")
    local tricky = 'he said "hi"\nsecond line\ttabbed — unicode: ✓'
    c:insert_one("fidelity", { _id = 1, note = tricky })
    t:expect(c:find_one("fidelity", { _id = 1 }).note):equals(tricky)
    -- and as a QUERY value, not just a stored one
    t:expect(c:count("fidelity", { note = tricky })):equals(1)
    c:drop("fidelity")
  end)

  g:test("eval is the JS escape hatch; ping is the health check", function(t)
    local c = t:use(db).client
    t:expect(c:ping()):equals("1")
    t:expect(c:eval("1 + 1")):equals("2")
    t:expect(c:eval("db.getName()")):equals("orders")   -- the opts.database plumbed through
  end)

  g:test("url is the mongodb endpoint for the app under test", function(t)
    t:expect(t:use(db).url):matches("^mongodb://")
  end)
end)
