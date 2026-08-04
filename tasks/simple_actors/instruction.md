## What You Must Build

In `/app/actor.py`, build an actor decorator: the actor runs in a spawned
subprocess. All exposed methods are async. Methods with leading underscores,
fields, and non-sync methods are not exposed. It must be possible to pass actor
reference between actors. Method calls are just asynchronous calls. Object
creation must be synchronous and return an actor reference.

Here is an example:

```python
import asyncio
from actor import actor

@actor
class Counter:
    def __init__(self, initial: int) -> None:
        self.value = initial

    async def add(self, amount: int) -> int:
        self.value += amount
        return self.value

async def main() -> None:
    counter = Counter(10)
    print(await counter.add(2)) # prints 12
    # counter.value would error because counter is not in this process

if __name__ == "__main__":
    asyncio.run(main())
```
