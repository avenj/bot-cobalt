use Test::More tests => 8;
use strict; use warnings;

use Fcntl qw/:flock/;
use File::Spec;
use File::Temp qw/ tempfile tempdir /;

BEGIN {
  use_ok( 'Bot::Cobalt::Core' );
  use_ok( 'Bot::Cobalt::Plugin::RDB::Database' );
}

my $core = Bot::Cobalt::Core->instance(
  cfg => {},
  var => '',
);

my $workdir = File::Spec->tmpdir;
my $tempdir = tempdir( CLEANUP => 1, DIR => $workdir );

my ($fh, $path) = _newtemp();
my $rdb = new_ok( 'Bot::Cobalt::Plugin::RDB::Database' => [
    RDBDir => $tempdir,
  ]
);

ok( $rdb->createdb('test'), 'createdb()' );

ok( ! $rdb->get_keys('test'), 'empty db' );

my $newkey;
ok( $newkey = $rdb->put('test', { Test => 1 }), 'Add key' );

is_deeply( $rdb->get('test', $newkey), { Test => 1 }, 'Retrieve key' );

## FIXME test search, random

ok( $rdb->deldb('test'), 'deldb()' );

sub _newtemp {
  my ($fh, $filename) = tempfile( 'tmpdbXXXXX',
    DIR => $tempdir, UNLINK => 1,
  );
  flock $fh, LOCK_UN;
  return($fh, $filename)
}
