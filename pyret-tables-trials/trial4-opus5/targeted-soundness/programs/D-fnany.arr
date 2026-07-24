fun as-any(x) -> Any: x end
mk = lam() -> Table<{age :: Number}>:
  as-any(table: age :: String row: \"x\" end)
end
