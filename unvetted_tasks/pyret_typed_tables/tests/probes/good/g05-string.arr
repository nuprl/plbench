provide *
fun greet(name :: String) -> String:
  "hello " + name
end
check:
  greet("world") is "hello world"
end
