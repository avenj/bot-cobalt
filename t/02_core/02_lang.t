use Test::More tests => 5;
use strict; use warnings;

BEGIN {
  use_ok( 'Bot::Cobalt::Lang' );
}

use Module::Build;
use Try::Tiny;
use File::Spec;

my $basedir;
try {
  $basedir = Module::Build->current->base_dir
} catch {
  die "\n! Failed to retrieve base_dir() from Module::Build\n"
     ."...are you trying to run the test suite outside of `./Build`?\n"
};

my $langdir = File::Spec->catdir( $basedir, 'etc', 'langs' );

my $english = new_ok( 'Bot::Cobalt::Lang' => [
    use_core => 1,
    
    lang => 'english',
    lang_dir => $langdir,
  ],
);

ok(keys %{ $english->rpls }, 'english set has RPLs' );

my $ebonics = new_ok( 'Bot::Cobalt::Lang' => [
    lang => 'ebonics',
    lang_dir => $langdir,
  ],
);

ok( keys %{ $ebonics->rpls }, 'ebonics set has RPLs' );
