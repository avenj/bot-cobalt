use Test::More tests => 2;
use Test::Cmd;

use strict; use warnings;

my $cmd = new_ok( 'Test::Cmd' => [
    workdir => '',
    prog    => 'blib/script/cobalt2',
 ],
);

is( $cmd->run(args => '-h'), 0, 'cobalt2 exit 0' );
