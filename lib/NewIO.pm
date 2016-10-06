use nqp;

my constant Path = IO::Path;

my class X::IO::Unsupported does X::IO {
    has $.operation;
    has $.typename;

    method message {
        "IO operation '$!operation' not supported by $!typename";
    }
}

my role IO { ... }
my role IO::Stream { ... }

my class IO::Handle {
    use fatal;

    my constant @ops = <
        get getc put print print-nl
        uniread uniwrite uniget unigetc uniputc
        read write getbyte putbyte
        slurp-rest line-seq
    >;

    has $.stream handles @ops;

    method new(IO::Stream:D $stream) {
        self.bless(:$stream);
    }

    method reopen {
        CATCH { .fail when X::IO }
        $!stream .= reopen(|%_);
        self;
    }

    method close(--> True) {
        CATCH { .fail when X::IO }
        $!stream.close(|%_);
        $!stream = IO::Stream::Closed;
    }
}

my role IO {
    use fatal;

    method open-stream { ... }

    method open {
        CATCH { .fail when X::IO }
        IO::Handle.new(self.open-stream(|%_));
    }

    method slurp {
        CATCH { .fail when X::IO }
        self.open-stream(|%_).slurp-rest(:close);
    }

    proto method spurt($ --> True) { CATCH { .fail when X::IO }; {*} }
    multi method spurt(Str:D \x) {
        my \stream = self.open-stream(|(%_ || :w));
        LEAVE stream.close;
        stream.print(x);
    }
    multi method spurt(Blob:D \x) {
        my \stream = self.open-stream(:bin, |(%_ || :w));
        LEAVE stream.close;
        stream.write(x);
    }
    multi method spurt(Uni:D \x) {
        my \stream = self.open-stream(:uni, |(%_ || :w));
        LEAVE stream.close;
        stream.uniwrite(x);
    }

    method lines {
        CATCH { .fail when X::IO }
        self.open-stream(|%_).line-seq(:close);
    }
}

my role IO::Stream {
    sub unsupported(&method) is hidden-from-backtrace {
        die X::IO::Unsupported.new(
            operation => &method.name,
            typename => ::?CLASS.^name);
    }

    method close { unsupported &?ROUTINE }
    method reopen { unsupported &?ROUTINE }
    method get { unsupported &?ROUTINE }
    method getc { unsupported &?ROUTINE }
    method put(Str:D) { unsupported &?ROUTINE }
    method print(Str:D) { unsupported &?ROUTINE }
    method print-nl { unsupported &?ROUTINE }
    method uniread(Int:D) { unsupported &?ROUTINE }
    method uniwrite(Uni:D) { unsupported &?ROUTINE }
    method uniget { unsupported &?ROUTINE }
    method unigetc { unsupported &?ROUTINE }
    method uniputc(uint32) { unsupported &?ROUTINE }
    method read(Int:D) { unsupported &?ROUTINE }
    method write(Blob:D) { unsupported &?ROUTINE }
    method getbyte { unsupported &?ROUTINE }
    method putbyte(uint8) { unsupported &?ROUTINE }
    method slurp-rest { unsupported &?ROUTINE }
    method line-seq { unsupported &?ROUTINE }
}

my role IO::Stream::Str does IO::Stream {
    method close { ... }
    method get { ... }
    method getc { ... }
    method put(Str:D) { ... }
    method print(Str:D) { ... }
    method print-nl { ... }
    method slurp-rest { ... }
    method line-seq { ... }
}

my role IO::Stream::Uni does IO::Stream {
    method close { ... }
    method uniread(Int:D) { ... }
    method uniwrite(Uni:D) { ... }
    method uniget { ... }
    method unigetc { ... }
    method uniputc(uint32) { ... }
    method slurp-rest { ... }
}

my role IO::Stream::Bin does IO::Stream {
    method close { ... }
    method read(Int:D) { ... }
    method write(Blob:D) { ... }
    method getbyte { ... }
    method putbyte(uint8) { ... }
    method slurp-rest { ... }
}

my class IO::Stream::Closed does IO::Stream {}

my role IO::FileStream {
    has $.raw;

    submethod BUILD(Mu :$raw) {
        $!raw := nqp::decont($raw);
    }

    method new(Str:D $path, Str:D $mode) {
        CATCH { X::IO.new(os-error => .message).fail }
        self.bless(raw => nqp::open($path, $mode));
    }

    method close(--> True) {
        CATCH { X::IO.new(os-error => .message).fail }
        nqp::closefh($!raw);
    }
}

my class IO::FileStream::Str does IO::FileStream does IO::Stream::Str {
    method get {
        my str $str;
        my Mu $fh := self.raw;
        nqp::stmts(
            ($str = nqp::readlinechompfh($fh)),
            # loses last empty line because EOF is set too early, RT #126598
            nqp::if(nqp::chars($str) || !nqp::eoffh($fh),
                $str,
                Nil
            )
        )
    }

    method getc { !!! }
    method put(Str:D) { !!! }
    method print(Str:D) { !!! }
    method print-nl { !!! }
    method slurp-rest { !!! }

    method line-seq(:$close) {
        Seq.new(class :: does Iterator {
            has $!handle;
            has $!close;

            method !SET-SELF(\handle, $!close) {
                $!handle := handle;
                self
            }
            method new(\handle, \close) {
                nqp::create(self)!SET-SELF(handle, close);
            }
            method pull-one() is raw {
                $!handle.get // do {
                    $!handle.close if $!close;
                    IterationEnd
                }
            }
            method push-all($target --> IterationEnd) {
                my $line;
                $target.push($line) while ($line := $!handle.get).DEFINITE;
                $!handle.close if $close;
            }
        }.new(self, $close));
    }
}

my class IO::FileStream::Bin does IO::FileStream does IO::Stream::Bin {
    method read(Int:D) { !!! }
    method write(Blob:D) { !!! }
    method getbyte { !!! }
    method putbyte(uint8) { !!! }

    method slurp-rest(:$close) {
        CATCH { X::IO.new(os-error => .message).fail }
        LEAVE self.close if $close;

        my $res := buf8.new;
        loop {
            my $buf := nqp::readfh($!raw, buf8.new, 0x100000);
            nqp::elems($buf)
              ?? $res.append($buf)
              !! return $res;
        }
    }
}

my class IO::FileStream::Uni does IO::FileStream does IO::Stream::Uni {
    method uniread(Int:D) { !!! }
    method uniwrite(Uni:D) { !!! }
    method uniget { !!! }
    method unigetc { !!! }
    method uniputc(uint32) { !!! }
    method slurp-rest { !!! }
}

my role IO::FileIO does IO {
    sub mode(
        :$r, :$w, :$x, :$a, :$update,
        :$rw, :$rx, :$ra,
        :$mode is copy,
        :$create is copy,
        :$append is copy,
        :$truncate is copy,
        :$exclusive is copy,
        *%
    ) {
        $mode //= do {
            when so ($r && $w) || $rw { $create              = True; 'rw' }
            when so ($r && $x) || $rx { $create = $exclusive = True; 'rw' }
            when so ($r && $a) || $ra { $create = $append    = True; 'rw' }

            when so $r { 'ro' }
            when so $w { $create = $truncate  = True; 'wo' }
            when so $x { $create = $exclusive = True; 'wo' }
            when so $a { $create = $append    = True; 'wo' }

            when so $update { 'rw' }

            default { 'ro' }
        }

        $mode = do given $mode {
            when 'ro' { 'r' }
            when 'wo' { '-' }
            when 'rw' { '+' }
            default { die "Unknown mode '$_'" }
        }

        $mode = join '', $mode,
            $create    ?? 'c' !! '',
            $append    ?? 'a' !! '',
            $truncate  ?? 't' !! '',
            $exclusive ?? 'x' !! '';

        $mode;
    }

    method abspath { ... }

    proto method open-stream { {*}.new(self.abspath, mode(|%_), |%_) }
    multi method open-stream(:$bin!) { IO::FileStream::Bin }
    multi method open-stream(:$uni!) { IO::FileStream::Uni }
    multi method open-stream { IO::FileStream::Str }
}

my class IO::Path is Path does IO::FileIO {}

sub EXPORT { BEGIN Map.new((IO => IO)) }
