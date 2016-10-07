# RFC: IO Frontend Redesign

The new IO subsystem would provide two roles `IO` and `IO::Stream` as well as the class `IO::Handle`.

`IO` objects are used to create `IO::Stream` objects via `open-stream` and `IO::Handle` objects via `open`. `IO::Handle` delegates to an underlying `IO::Stream` to do the actual work.

Any user-supplied class that does `IO` only needs to implement the `open-stream` method, and will get `open` for free as well as methods like `slurp`, `spurt` or `lines` that implicitly open and close a stream.

The `IO::Handle` class is generic and does not need to be customized. It exists so we can switch between encodings as well as binary and grapheme-based IO by replacing the underlying streams.

The `IO::Stream` role contains methods for both binary and grapheme-based IO, but the default implementations just die with `X::IO::Unsupported`.

I'd also like to support IO at the codepoint level in terms of the `Uni` type. For that purpose, I suggest adding the methods

    method uniread(Int --> Uni) { ... }
    method uniwrite(Uni --> True) { ... }
    method uniget(--> Uni) { ... }
    method unigetc(--> uint32) { ... }
    method uniputc(uint32 --> True) { ... }

A partial implementation of the proposal can be found in this repository.
