# RFC: IO Frontend Redesign

The new IO subsystem would provide two roles `IO` and `IO::Stream` as well as the class `IO::Handle`.

`IO` objects are used to create `IO::Handle` objects which in turn delegate to `IO::Stream` objects to do the actual work.

Any user-supplied class that does `IO` needs to implement the `open` method, but will get methods like `slurp`, `spurt` or `lines` that automatically call `open` for free.

The `IO::Handle` class is generic and does not need to be customized. It exists so we can switch between encodings as well as binary and grapheme-based IO by replacing the underlying streams.

The `IO::Stream` role contains methods for both binary and grapheme-based IO, but the default implementations just die with `X::IO::Unsupported`.

I'd also like to support IO at the codepoint level in terms of the `Uni` type. For that purpose, I suggest adding the methods

    method uniread(Int --> Uni) { ... }
    method uniwrite(Uni --> True) { ... }
    method uniget(--> Uni) { ... }
    method unigetc(--> uint32) { ... }
    method uniputc(uint32 --> True) { ... }

A partial implementation of the proposal can be found in this repository.
