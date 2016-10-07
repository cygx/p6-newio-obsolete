use lib 'lib';
use NewIO;
use fatal;

say IO::Path.^roles;

my $path = IO::Path.new('test.p6');
print $path.slurp(:bin).decode;
.perl.say for $path.lines(:!chomp);
say $path.words.Bag;
