local paths = {
  "/people",
  "/people",
  "/people",
  "/people/users/top",
  "/people/repositories/top",
  "/organizations",
  "/users/github/alice",
  "/languages",
  "/languages/ruby",
  "/packages",
  "/packages/npm",
  "/badges/users/github/alice.svg"
}

local counter = 0

request = function()
  counter = counter + 1
  local path = paths[(counter % #paths) + 1]
  return wrk.format("GET", path, {
    ["Accept-Language"] = "pl",
    ["User-Agent"] = "polish-open-source-rank-wrk/1.0"
  })
end
