use lib 'lib';
use NewIO;

say IO::Path.^roles;
print IO::Path.new('test.p6').slurp(:bin).decode;
