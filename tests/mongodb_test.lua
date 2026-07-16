-- Self-test for prova-mongodb: provision MongoDB, then an insert + count + find + delete round-trip
-- through the docker-exec mongosh CLI. Requires docker; skips otherwise.

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

    local doc = c:find_one("items", { _id = 1 })
    t:expect(doc.name):equals("alpha")
    t:expect(doc.qty):equals(3)

    local rows = c:find("items")
    t:expect(#rows):equals(2)

    t:expect(c:delete_many("items", { name = "beta" })):equals(1)
    t:expect(c:count("items")):equals(1)
  end)

  g:test("url is the mongodb endpoint for the app under test", function(t)
    t:expect(t:use(db).url):matches("^mongodb://")
  end)
end)
