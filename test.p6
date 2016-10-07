use lib 'lib';
use NewIO;
use fatal;

say IO::Path.^roles;

my $path = IO::Path.new('.gitignore');
$path.open.close;

given $path.open {
    say .stream.^name;
    say .reopen(:bin).stream.^name;
    .close;
}

say $path.slurp(:bin).decode.perl;
.perl.say for $path.lines(:!chomp);
say $path.words.Bag;
