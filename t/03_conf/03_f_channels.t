use Test::More tests => 4;
use strict; use warnings;


BEGIN {
  use_ok( 'Bot::Cobalt::Conf::File::Channels' );
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

my $chan_cf_path = File::Spec->catfile( $basedir, 'etc', 'channels.conf' );

my $chancf = new_ok( 'Bot::Cobalt::Conf::File::Channels' => [
    path => $chan_cf_path,
  ],
);

isa_ok( $chancf, 'Bot::Cobalt::Conf::File' );

ok( ref $chancf->context('Main') eq 'HASH', 'context(Main) isa HASH' );

