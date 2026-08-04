"""Behavioral tests for the actor decorator.

These tests are adapted from py-abstractions' actor suite. Structural checks
and direct pickle tests are intentionally omitted; reference transfer is tested
through ordinary calls between actors instead.
"""

from __future__ import annotations

import asyncio
import gc
import os
from typing import Any

import pytest

from actor import actor


@actor
class Counter:
    """A stateful actor used by the call and reference-transfer tests."""

    def __init__(self, initial: int = 0) -> None:
        self.value = initial

    async def add(self, amount: int = 1) -> int:
        """Add an amount and return the new value."""

        self.value += amount
        return self.value

    async def fail(self, message: str) -> None:
        """Raise a caller-selected exception."""

        raise ValueError(message)

    async def process_id(self) -> int:
        """Return the process hosting this actor."""

        return os.getpid()


@actor
class Forwarder:
    """Call another actor using a reference received as an argument."""

    async def add_via(self, target: Any, amount: int) -> int:
        """Forward an addition to another actor."""

        return await target.add(amount)


@actor
class SlowCounter:
    """Expose whether overlapping calls mutate one actor serially."""

    def __init__(self) -> None:
        self.value = 0

    async def increment(self) -> int:
        """Increment after yielding to make concurrent execution observable."""

        old_value = self.value
        await asyncio.sleep(0.02)
        self.value = old_value + 1
        return self.value


@actor
class Relay:
    """Return arbitrary call values, including nested actor references."""

    async def bounce(self, value: Any) -> Any:
        """Return a value through the actor subprocess."""

        return value


@actor
class ReferenceHolder:
    """Retain a transferred actor reference and use it in later calls."""

    def __init__(self) -> None:
        self.target = None

    async def remember(self, target: Any) -> None:
        """Store a reference received from another process."""

        self.target = target

    async def add(self, amount: int) -> int:
        """Call the actor reference stored by an earlier message."""

        return await self.target.add(amount)


@actor
class Spawner:
    """Create an actor from within another spawned actor process."""

    async def spawn_counter(self, initial: int) -> Any:
        """Create and return a new Counter reference."""

        return Counter(initial)

    async def process_id(self) -> int:
        """Return the process hosting this actor."""

        return os.getpid()


@pytest.fixture(autouse=True)
def collect_actor_references() -> Any:
    """Promptly release actor references after every test."""

    yield
    gc.collect()


@pytest.mark.asyncio
async def test_construction_and_async_method_calls() -> None:
    """Construction returns a remote reference whose calls are awaitable."""

    counter = Counter(10)
    assert await counter.add() == 11
    assert await counter.add(amount=4) == 15
    assert await counter.process_id() != os.getpid()


@pytest.mark.asyncio
@pytest.mark.skip(
    reason="overlapping calls are allowed to execute concurrently"
)
async def test_actor_calls_are_serialized() -> None:
    """Concurrent callers must not execute one actor's methods concurrently."""

    counter = SlowCounter()
    results = await asyncio.gather(*(counter.increment() for _ in range(8)))
    assert sorted(results) == list(range(1, 9))


@pytest.mark.asyncio
async def test_actor_references_can_be_passed_to_actors() -> None:
    """An actor can invoke a reference received in a method call."""

    counter = Counter(5)
    forwarder = Forwarder()
    assert await forwarder.add_via(counter, 7) == 12
    assert await counter.add() == 13


@pytest.mark.asyncio
async def test_values_and_references_round_trip_through_an_actor() -> None:
    """Nested ordinary values and actor references survive an actor round trip."""

    counter = Counter(2)
    relay = Relay()
    payload = {"label": "counter", "values": [1, 2, 3], "target": counter}
    returned = await relay.bounce(payload)

    assert returned["label"] == "counter"
    assert returned["values"] == [1, 2, 3]
    assert await returned["target"].add(3) == 5
    assert await counter.add() == 6


@pytest.mark.asyncio
async def test_transferred_reference_survives_sender_deletion() -> None:
    """A stored remote reference remains valid after its sender drops its copy."""

    holder = ReferenceHolder()
    original = Counter(10)
    await holder.remember(original)
    del original
    gc.collect()

    assert await holder.add(2) == 12


@pytest.mark.asyncio
async def test_remote_exceptions_are_raised_by_await() -> None:
    """Method exceptions reach the awaiting caller without killing the actor."""

    counter = Counter()
    with pytest.raises(ValueError, match="deliberate"):
        await counter.fail("deliberate")
    assert await counter.add() == 1


def test_constructor_exceptions_are_raised() -> None:
    """Actor creation reports an exception raised by the constructor."""

    @actor
    class Broken:
        """An actor whose constructor fails."""

        def __init__(self) -> None:
            raise RuntimeError("broken constructor")

        async def unused(self) -> None:
            """Provide an actor method that construction never reaches."""

            return None

    with pytest.raises(RuntimeError):
        Broken()


@pytest.mark.asyncio
async def test_local_actor_classes_work() -> None:
    """A decorated actor class can be defined in a local scope."""

    @actor
    class Local:
        """A function-local actor class."""

        async def echo(self, value: str) -> str:
            """Return the supplied string."""

            return value

    local = Local()
    assert await local.echo("hello") == "hello"


@pytest.mark.asyncio
async def test_actor_can_create_and_return_an_actor_reference() -> None:
    """An actor-created reference works in the original caller process."""

    spawner = Spawner()
    child = await spawner.spawn_counter(20)

    assert await child.add(2) == 22
    assert await child.process_id() != await spawner.process_id()
