use Test::More tests => 10;
use strict; use warnings;

BEGIN {
  use_ok( 'Bot::Cobalt::Conf' );
}

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

my $conf = new_ok( 'Bot::Cobalt::Conf' => [
    etc => $etcdir,
  ],
);

### Path attribs:
## path_to_core_cf
## path_to_channels_cf
## path_to_irc_cf
## path_to_plugins_cf

ok( $conf->'path_to_'.$_, "attrib $_" )
  for qw/ core_cf channels_cf irc_cf plugins_cf /;

### Config objects:
## ->core
## ->irc
## ->channels
## ->plugins

isa_ok( $conf->core, 'Bot::Cobalt::Conf::File::Core' );

isa_ok( $conf->irc, 'Bot::Cobalt::Conf::File::IRC' );

isa_ok( $conf->channels, 'Bot::Cobalt::Conf::File::Channels' );

isa_ok( $conf->plugins, 'Bot::Cobalt::Conf::File::Plugins' );
