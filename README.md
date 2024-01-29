# Sharing memory with a Web Worker

We want to pass a pointer to a web worker and allow the worker to read the value the pointer points
to.

We can pass the pointer, but we don't get the expected value when reading from it. I believe it's
because the worker has its own heap, separate from the main thread.

I tried to overcome this by figuring out how to share the heap, but failed. Attempts are:

A) Compiling with `+atomics,+mutable-globals,+bulk-memory` (see `.cargo/config.toml`) and;

B) Compiling `lib` with `-Zbuild-std=std,panic_abort`.

## Running

1. Run like so:

```
cargo leptos watch --lib-cargo-args='-Zbuild-std=std,panic_abort'
```

2. Open the application (https://localhost:3000).

3. Open the browser console.

4. Click the button in the application's UI.

5. The console will log "Worker got: 0" and "main: 0".

In step 5 we would have wanted "Worker got: 5" and "main: 5".
