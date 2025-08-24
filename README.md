# zig-datagram

Pretty good single file Zig 0.14.1 wrapper for Unix domain datagram sockets.

Look at the test cases in the file for how to use it.

## TODO

- [ ] Transition to Zig 0.15.1

## Style guidelines

- Try to use [TIGER_STYLE](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md), with some caviats, as described below.

### Testing conventions

- Use "design by contract"
  - This pretty much just means using a lot of asserts like this:
    - **Preconditions**: what must be true about the inputs to a function?
    - **Invariants**: what must be true about the state of the system?
    - **Postconditions**: what must be true about the outputs of a function?
  - If any of these conditions are violated, YOUR CODE HAS A BUG.
    - e.g. Someone using a function wrong should trigger an assert, not an error.
- Use errors to check external conditions, like user input.
- High test coverage != high quality code
  - 100% coverage can be a huge waste of time and can lull you into a false sense of security.
    - For example, your function could fail to handle an edge case, even if you have 100% coverage.
  - Slows CI builds (not really a concern for small projects, but something to consider)
  - Test for edge cases:
    - **Valid data**
    - **Invalid data**
    - **Initially valid data that becomes invalid**
  - Interesting way to get code coverage data: https://zig.news/squeek502/code-coverage-for-zig-1dk1
- Use static analysis?
  - I'm not really sure how to do that for Zig.
  - Interesting idea for a lifetime checker: https://github.com/ityonemo/clr

### Naming conventions

- Believe it or not, names can be too descriptive.
  - Short names can be MORE readable because they're instantly recognizable.
  - We have namespaces for a reason. Rule of thumb: if you're variable's name contains the name of the namespace it's in, you're doing something wrong.

### Naming Syntax

- **Functions**: lowerCamelCase
  - Function whose return type is `type`: UpperCamelCase
  - **Parameters**: snake_case
- **Types**: UpperCamelCase
  - Abbreviations: capitalize appropriately, e.g. `HTTPClient`
- **Variables**: snake_case
  - Including comptime variables (not constants)
- **Fields**: snake_case
- **Enum or Error values**: UpperCamelCase
  - Abbreviations: capitalize appropriately, e.g. `HTTPClient`
  - Shallow wrapper of C enum values: UPPER_SNAKE_CASE
- **Comptime constant** values: UPPER_SNAKE_CASE
- **Files**:
  - The file is a namespace: snake_case (even with abbreviations in the name)
  - The file is itself an importable type: conform to the **Types** naming convention.
- **Directories**: TODO...the zig language repo doesn't seem to have a standard.
- **Tests** (WORK IN PROGRESS): test "functionName/when <condition>/then <result>"
  - "functionName" conforms to the **Functions** naming convention.
  - "condition" and "result" are descriptive but concise natural language.

### Commenting

- Most code should be self-documenting-ish.
- Comment things you don't want to forget.
  - Comment "why" you did what you did.
- Not every comment needs to be a full, eloquent sentence.
  - Sometimes short comments are actually more readable because they're instantly recognizable.
