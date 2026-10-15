# Agent Development Rules

## Test-driven development is mandatory

This project must be developed from the test file at `tests/mvp.test.md`.

For every product or code change, the agent must:

1. Read the current product design and the relevant test cases.
2. Add or update a test case before implementing the behavior.
3. Implement the smallest change needed to satisfy the test.
4. Run the available test command or validation procedure.
5. Update the test status and record any remaining failure.
6. Do not mark a feature complete unless its test passes.

The test file is a living product contract. When the product requirement changes, update the test file first and then update the implementation.

## MVP scope

The MVP is a personal daily drink log:

- one user records their own drinks;
- one record represents exactly one drink;
- users can select a menu drink or create a custom drink;
- a record can include time, photo, brand, drink style, cup/size, sweetness, temperature, ice level, location, and notes; toppings are not recorded;
- nutrition data prefers official data, otherwise it must be labeled as an estimate;
- missing nutrition data must be shown as unavailable rather than presented as precise data.

Do not reintroduce the previous multi-user collaborative List behavior unless the product design is explicitly changed.

## Completion standard

Before reporting a feature as complete, provide:

- the tests added or changed;
- the validation command or procedure used;
- the result;
- any known limitation.
