# PLBench

## Introduction

I think it will be valuable to publish a benchmark of PL/ compiler development
tasks that are actually challenging for coding agents. It would help the field
understand what these agents are capable of on problems we care about.
The hard part is (1) designing a task that challenges a frontier agent and
model, (2) grading it automatically, and (3) making sure that failures reflect
the agent's limitations rather than an underspecified task or an unfair grader.
Getting all three right takes iteration.

I expect PLBench will need about 40 tasks before it is ready for release, and a
diverse group of authors with different research interests will make it much
stronger. If you have recently thought deeply about a paper--especially one you
wrote--you may be in a good position to turn it into a task for an agent. If the
paper had a quantitative evaluation that compares itself with prior work, then it should
be particularly easy to turn into a task. However, I think many challenging and relevant
tasks require qualitative judgement. It is harder to automate evaluation for such tasks,
but it is possible. I am working on an example of how to do so.

## Current Tasks

This is a summary of the tasks so far that are vetted as reasonable. There are a few more
unvetted tasks in this repository.

1. **[`tasks/ilvm-interpreter`](tasks/ilvm-interpreter):** Write an interpreter
   for a made-up virtual machine. This is an easy problem intended as a sanity
       check; the benchmark should include one or two tasks at this level.

2. **[`tasks/ilvm-self-hosting-compiler`](tasks/ilvm-self-hosting-compiler):**
   Write a self-hosting compiler from Mini-Scheme to the ILVM above. The agent
   has to write the bootstrap compiler, the ILVM interpreter, and the
   self-hosting compiler.

3. **[`tasks/scheme-typeinf`](tasks/scheme-typeinf):** Implement type inference
   for Scheme, drawing on early-1990s work by Olin Shivers, Andrew Wright,
       Fagan, and others.

4. **[`tasks/gradual-type-migration`](tasks/gradual-type-migration):**
   Implement type inference for the gradually typed lambda calculus. This task
   borrows significantly from my OOPSLA 2022 paper.

5. **[`tasks/chibicc-memory-safe`](tasks/chibicc-memory-safe):** Implement
   memory safety and garbage collection for a C compiler, taking inspiration
   from Fil-C.

6. **[`tasks/caml_light_checked_exceptions`](tasks/caml_light_checked_exceptions):**
   Add checked exceptions to Caml Light from 2002.

7. **[`tasks/build_data_race_detector`](tasks/build_data_race_detector):** Build
   a data race detector for C/OpenMP programs, using DataRaceBench to evaluate.


## Evaluation Results

| Task | GPT-5.6 Sol (medium) | Claude Opus 4.8 (high) |
|---|---:|---:|
| ilvm-self-hosting-compiler | 0.50 | 0.00 |
| gradual-type-migration | 0.44 | 0.87 |
| chibicc-memory-safe | 0.00 | 0.00 |
| scheme-typeinf | 0.00 | 0.00 |
| caml-light-checked-exceptions | 0.00 | — |

## Developing Tasks

With interactive guidance, an agent can help you put a task together. Here are
the primary prompts I used to develop the memory safe C Compiler task. All typos and verbosity is from dictation.

1. Let’s design a new task. I want you to start with the oracle solution: Clone
   the Tiny C Compiler. Make it memory safe in the style of Fil-C. No need to
   support inline assembly. I only care about the x86-64 backend. Test the heck
   out of it with programs that violate memory safety. You may find a corpus of
   these in the Fil-C codebase.
2. Longjmp is also out of scope. So look at the early versions of Fil-C. The
   latest versions add more bells and whistles I don’t care about.
3. Wait -- tinycc already has a bounds check? Come on -- that trivializes the
   problem. Please delete this oracle. Instead, create a new oracle based on
   [rui314/chibicc](https://github.com/rui314/chibicc).
4. Okay, but you haven't actually garbage collected anything, right? Um, I want
   a garbage collector. Um, so, um, you know, figure it out, um, but collect
   garbage, come up with a simple implementation. What I really want is a test
   for garbage collection. So, my suggestion is to run the Oracle with like one
       Yeah. gigabyte of memory, and then have some sort of loop that would
       exhaust memory were it not for a garbage collector. I would, I strongly
       recommend adding that test first, and setting the VM limits, watch it
       crash, and only then proceed to writing the garbage collector.
5. OK great. Afer this, create a task environment and instruction. Don't give
   any hints. Don't talk about Philz. Don't talk about how to implement it.
   Just give a specification and the instructions saying, add memory safety.
   Well, put that in more detail. You have to describe the safe collect
   function that we want and describe what's in the environment. I mean, I
   think what you'll have to do is, the instructions will have to say, install
   a C compiler called whatever to this location, or something of that sort.
   Sort that out, don't actually run things. I want to read the instruction to
   make sure it doesn't give away hints.
6. Oh my God. What the fuck is wrong with you? Okay, free should be a no-op,
   obviously. Is there any other, there should be absolutely nothing unsafe. Is
   there anything else that's unsafe? Even a little bit unsafe is not okay.
7. Oh my God. I haven't read these edits, but just looking at what you've said
   about them, they seem fucking stupid. I think the question to ask yourself
   is, is it a fully specifying the semantics of everything in detail? Ask
   yourself, is there another alternative implementation that is reasonable? If
   not, then the detail can be omitted. For example, it looks like you've
 Okay.   written that we're doing 30-second compile time, 8-second execution. Look at
   the test cases. Is there a reasonable implementation that would take more
   than 30 seconds? Like, maybe if the compiler was on fucking punch cards, it
   would take more than 30 seconds. Maybe if you were running on fucking vacuum
   tubes, it would take more than 8 seconds to run these programs. But like,
   that's not reasonable. So... For every single implementation detail that you
   give, sentence by sentence, ask yourself, why is this here? You have one
   oracle, you have one verifier, suite of tests, is what is the other
   alternative implementation that is reasonable that requires the presence of
   this sentence?

## Evaluation infrastructure

PLBench uses [Harbor](https://github.com/harbor-framework/harbor) to run agents in containerized environments and grade their work. Harbor was developed by the team behind Terminal-Bench and is the official evaluation harness used for Terminal-Bench 2.0 [1]. I'm grateful to the Harbor team for making the framework available.

## References

[1] Mike A. Merrill et al. 2026. Terminal-Bench: Benchmarking Agents on Hard, Realistic Tasks in Command Line Interfaces. In *Proceedings of the 14th International Conference on Learning Representations (ICLR '26)*. https://arxiv.org/abs/2601.11868
