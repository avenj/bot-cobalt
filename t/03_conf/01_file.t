use Test::More tests => 6;
use strict; use warnings;


BEGIN {
  use_ok( 'Bot::Cobalt::Conf::File' );
}

use Module::Build;

use File::Spec;

my $basedir;

use Try::Tiny;
try {
  $basedir = Module::Build->current->base_dir  
} catch {
  die 
    "\nFailed to retrieve base_dir() from Module::Build\n",
    "... are you trying to run the test suite outside of `./Build`?\n",
};

my $etcdir = File::Spec->catdir( $basedir, 'etc' );

my $cfg_obj = new_ok( 'Bot::Cobalt::Conf::File' => [
    path => File::Spec->catfile( $etcdir, 'cobalt.conf' )
  ],
);

my $this_hash;
ok( $this_hash = $cfg_obj->cfg_as_hash, 'cfg_as_hash()' );

ok( ref $this_hash eq 'HASH', 'cfg_as_hash isa HASH' );

ok( $cfg_obj->rehash, 'rehash()' );

is_deeply( $cfg_obj->cfg_as_hash, $this_hash );
