use Test::More tests => 11;
use strict; use warnings;


BEGIN {
  use_ok( 'Bot::Cobalt::Conf::File::Core' );
  use_ok( 'Bot::Cobalt::Conf::File::IRC' );
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
my $irc_cf_path  = FIle::Spec->catfile( $basedir, 'etc', 'multiserv.conf' );

my $corecf = new_ok( 'Bot::Cobalt::Conf::File::Core' => [
    path => $core_cf_path,
  ],
);

my $irccf = new_ok( 'Bot::Cobalt::Conf::File::IRC' => [
    path => $irc_cf_path,
    
    ## Required attrib
    ## Should pull ->irc() from Core
    core_config => $corecf,
  ],
);

isa_ok( $irccf, 'Bot::Cobalt::Conf::File' );

ok( $irccf->validate, 'validate()' );

ok( ref $irccf->list_contexts eq 'ARRAY', 'list_contexts() isa ARRAY' );

ok( ref $irccf->context('Main') eq 'HASH', 'context(MAIN) isa HASH' );

ok( $irccf->context('Main')->{Nickname}, 'context(MAIN) has Nickname' );
ok( $irccf->context('Main')->{Username}, 'context(MAIN) has Username' );
ok( $irccf->context('Main')->{Realname}, 'context(MAIN) has Realname' );
