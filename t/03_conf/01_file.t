use Test::More tests => 3;
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

ok( ref $cfg_obj->cfg_as_hash eq 'HASH', 'cfg_as_hash isa HASH' );
