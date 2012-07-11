use Test::More tests => 7;
use strict; use warnings;


BEGIN {
  use_ok( 'Bot::Cobalt::Conf::File::Core' );
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

my $core_cf_path = File::Spec->catfile( $basedir, 'etc', 'cobalt.conf' );

my $corecf = new_ok( 'Bot::Cobalt::Conf::File::Core' => [
    path => $core_cf_path,
  ],
);

isa_ok( $corecf, 'Bot::Cobalt::Conf::File' );

is( $corecf->language, 'english', 'language()' );

ok( ref $corecf->irc eq 'HASH', 'irc() isa HASH' );

ok( ref $corecf->opts eq 'HASH', 'opts() isa HASH' );

ok( ref $corecf->paths eq 'HASH', 'paths() isa HASH' );
