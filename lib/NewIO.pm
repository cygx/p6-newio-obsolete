use nqp;
use fatal;

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
my class IO::Stream::Closed { ... }

my class IO::Handle {
    has $.stream handles <
        get getc put print print-nl chomp readchars
        uniread uniwrite uniget unigetc uniputc
        read write getbyte putbyte
    >;

    method new(IO::Stream:D $stream) {
        self.bless(:$stream);
    }

    proto method reopen($?) {*}
    multi method reopen(IO::Stream:D $!stream) { self }
    multi method reopen {
        $!stream .= reopen(|%_);
        self;
    }

    method close(--> True) {
        $!stream.close(|%_);
        $!stream = IO::Stream::Closed;
    }

    method slurp-rest(:$close) {
        LEAVE self.close if $close;
        $!stream.slurp-rest(|%_);
    }

    method line-seq(:$close) {
        $!stream.line-seq(close => $close ?? self !! Nil, |%_);
    }

    method word-seq(:$close) {
        $!stream.word-seq(close => $close ?? self !! Nil, |%_);
    }
}

my role IO {
    method open-stream { ... }

    method open {
        IO::Handle.new(self.open-stream(|%_));
    }

    method slurp {
        self.open-stream(|%_).slurp-rest(:close);
    }

    proto method spurt($ --> True) {*}
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
        self.open-stream(|%_).line-seq(:close);
    }

    method words {
        self.open-stream(|%_).word-seq(:close);
    }
}

my role IO::Stream {
    sub unsupported(&method) is hidden-from-backtrace {
        die X::IO::Unsupported.new(
            operation => &method.name,
            typename => ::?CLASS.^name);
    }

    method !closeable($close) {
        $close === True ?? self !! $close // class { method close {} }
    }

    method close { unsupported &?ROUTINE }
    method reopen { unsupported &?ROUTINE }

    method get { unsupported &?ROUTINE }
    method getc { unsupported &?ROUTINE }
    method put(Str:D) { unsupported &?ROUTINE }
    method print(Str:D) { unsupported &?ROUTINE }
    method print-nl { unsupported &?ROUTINE }
    method chomp { unsupported &?ROUTINE }
    method readchars(Int:D $ = 0) { unsupported &?ROUTINE }

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

    method line-seq { Seq.new(self.line-iterator(|%_)) }
    method line-iterator { unsupported &?ROUTINE }

    method word-seq { Seq.new(self.word-iterator(|%_)) }
    method word-iterator { unsupported &?ROUTINE }
}

my role IO::Stream::Str does IO::Stream {
    method close { ... }
    method reopen { ... }
    method get { ... }
    method getc { ... }
    method put(Str:D) { ... }
    method print(Str:D) { ... }
    method print-nl { ... }
    method chomp { ... }
    method readchars(Int:D $?) { ... }
    method slurp-rest { ... }

    method line-iterator(:$close) {
        my \stream = self;
        my \closeable = self!closeable($close);

        nqp::create(class :: does Iterator {
            method pull-one() is raw {
                stream.get // do {
                    closeable.close;
                    IterationEnd
                }
            }

            method push-all($target --> IterationEnd) {
                my $line;
                $target.push($line) while ($line := stream.get).DEFINITE;
                closeable.close;
            }
        })
    }

    method word-iterator(:$close) {
        my \stream = self;
        my \closeable = self!closeable($close);

        class :: does Iterator {
            has str $!str;
            has int $!pos;
            has int $!searching;

            method new { nqp::create(self)!INIT-SELF }
            method !INIT-SELF {
                $!str = ''; # RT #126492
                $!searching = 1;
                self!next-chunk;
                self;
            }

            method !next-chunk() {
                my int $chars = nqp::chars($!str);
                $!str = $!pos < $chars ?? nqp::substr($!str,$!pos) !! "";
                $chars = nqp::chars($!str);

                while $!searching {
                    $!str = nqp::concat($!str,stream.readchars);
                    my int $new = nqp::chars($!str);
                    $!searching = 0 if $new == $chars; # end
                    $!pos = ($chars = $new)
                      ?? nqp::findnotcclass(
                           nqp::const::CCLASS_WHITESPACE, $!str, 0, $chars)
                      !! 0;
                    last if $!pos < $chars;
                }
            }

            method pull-one() {
                my int $chars;
                my int $left;
                my int $nextpos;

                while ($chars = nqp::chars($!str)) && $!searching {
                    while ($left = $chars - $!pos) > 0 {
                        $nextpos = nqp::findcclass(
                          nqp::const::CCLASS_WHITESPACE,$!str,$!pos,$left);
                        last unless $left = $chars - $nextpos; # broken word

                        my str $found =
                          nqp::substr($!str, $!pos, $nextpos - $!pos);
                        $!pos = nqp::findnotcclass(
                          nqp::const::CCLASS_WHITESPACE,$!str,$nextpos,$left);

                        return nqp::p6box_s($found);
                    }
                    self!next-chunk;
                }
                if $!pos < $chars {
                    my str $found = nqp::substr($!str,$!pos);
                    $!pos = $chars;
                    nqp::p6box_s($found)
                }
                else {
                    closeable.close;
                    IterationEnd
                }
            }

            method push-all($target --> IterationEnd) {
                my int $chars;
                my int $left;
                my int $nextpos;

                while ($chars = nqp::chars($!str)) && $!searching {
                    while ($left = $chars - $!pos) > 0 {
                        $nextpos = nqp::findcclass(
                          nqp::const::CCLASS_WHITESPACE,$!str,$!pos,$left);
                        last unless $left = $chars - $nextpos; # broken word

                        $target.push(nqp::p6box_s(
                          nqp::substr($!str, $!pos, $nextpos - $!pos)
                        ));

                        $!pos = nqp::findnotcclass(
                          nqp::const::CCLASS_WHITESPACE,$!str,$nextpos,$left);
                    }
                    self!next-chunk;
                }
                $target.push(nqp::p6box_s(nqp::substr($!str,$!pos)))
                  if $!pos < $chars;
                closeable.close;
            }
        }.new
    }
}

my role IO::Stream::Uni does IO::Stream {
    method close { ... }
    method reopen { ... }
    method uniread(Int:D) { ... }
    method uniwrite(Uni:D) { ... }
    method uniget { ... }
    method unigetc { ... }
    method uniputc(uint32) { ... }
    method slurp-rest { ... }

    method line-iterator(:$close) {
        my \stream = self;
        my \closeable = self!closeable($close);

        nqp::create(class :: does Iterator {
            method pull-one() is raw {
                stream.uniget // do {
                    closeable.close;
                    IterationEnd
                }
            }

            method push-all($target --> IterationEnd) {
                my $line;
                $target.push($line) while ($line := stream.uniget).DEFINITE;
                closeable.close;
            }
        })
    }
}

my role IO::Stream::Bin does IO::Stream {
    method close { ... }
    method reopen { ... }
    method read(Int:D) { ... }
    method write(Blob:D) { ... }
    method getbyte { ... }
    method putbyte(uint8) { ... }

    method slurp-rest(:$close) {
        my $buf := buf8.new;
        loop { $buf.append(self.read(0x100000) || last) }
        self.close if $close;
        $buf;
    }


}

my class IO::Stream::Closed does IO::Stream {}

my class IO::FileStream::Str { ... }
my class IO::FileStream::Uni { ... }
my class IO::FileStream::Bin { ... }

my role IO::FileStream {
    has $!raw;

    submethod BUILD(Mu :$raw) {
        self!SET-RAW($raw);
    }

    method !SET-RAW(Mu $raw) { $!raw := nqp::decont($raw) }

    method new(Str:D $path, Str:D $mode, :$chomp) {
        self.bless(raw => nqp::open($path, $mode), :$chomp);
    }

    method !REOPEN {}

    proto method reopen { self!REOPEN; {*}.bless(:$!raw, |%_) }
    multi method reopen(:$bin!) { IO::FileStream::Bin }
    multi method reopen(:$uni!) { IO::FileStream::Uni }
    multi method reopen(:$str?) { IO::FileStream::Str }

    method close(--> True) {
        nqp::closefh($!raw);
    }
}

my class IO::FileStream::Str does IO::FileStream does IO::Stream::Str {
    has Bool:D $.chomp is rw = True;

    submethod BUILD(Mu :$raw, :$chomp) {
        self!SET-RAW($raw);
        $!chomp = so $chomp if defined $chomp;
    }

    method !REOPEN {
        note '=> flushing decode buffers';
    }

    method get {
        my str $str;
        nqp::if($!chomp,
            nqp::stmts(
                ($str = nqp::readlinechompfh($!raw)),
                # loses last empty line because EOF is set too early, RT #126598
                nqp::if(nqp::chars($str) || !nqp::eoffh($!raw),
                    $str,
                    Nil
                )
            ),
            nqp::stmts(
                ($str = nqp::readlinefh($!raw)),
                # no need to check EOF
                nqp::if(nqp::chars($str),
                    $str,
                    Nil
                )
            )
        )
    }

    method getc { !!! }
    method put(Str:D) { !!! }
    method print(Str:D) { !!! }
    method print-nl { !!! }

    method readchars(Int:D $chars = $*DEFAULT-READ-ELEMS) {
        nqp::readcharsfh($!raw, nqp::unbox_i($chars));
    }

    method slurp-rest { !!! }
}

my class IO::FileStream::Bin does IO::FileStream does IO::Stream::Bin {
    method read(Int:D $bytes) {
        nqp::readfh($!raw, buf8.new, nqp::unbox_i($bytes));
    }

    method write(Blob:D) { !!! }
    method getbyte { !!! }
    method putbyte(uint8) { !!! }
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
    multi method open-stream(:$str?) { IO::FileStream::Str }
}

my class IO::Path is Path does IO::FileIO {}

sub EXPORT { BEGIN Map.new((IO => IO)) }
