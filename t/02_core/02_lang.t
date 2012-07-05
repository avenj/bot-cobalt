use Test::More tests => 69;
use strict; use warnings;

my %sets = (
  ## Last updated for SPEC: 7
  ## 58 tests
  CORE => [ qw/  
    RPL_NO_ACCESS
    RPL_DB_ERR
    RPL_PLUGIN_LOAD
    RPL_PLUGIN_UNLOAD
    RPL_PLUGIN_ERR
    RPL_PLUGIN_UNLOAD_ERR
    RPL_TIMER_ERR
  / ],
  
  IRC => [ qw/
    RPL_CHAN_SYNC
  / ],

  VERSION => [ qw/
    RPL_VERSION RPL_INFO RPL_OS
  / ],
  
  ALARMCLOCK => [ qw/
    ALARMCLOCK_SET
    ALARMCLOCK_NOSUCH
    ALARMCLOCK_NOTYOURS
    ALARMCLOCK_DELETED
  / ],
  
  AUTH => [ qw/
    AUTH_BADSYN_LOGIN
    AUTH_BADSYN_CHPASS
    AUTH_SUCCESS
    AUTH_FAIL_BADHOST
    AUTH_FAIL_BADPASS
    AUTH_FAIL_NO_SUCH
    AUTH_FAIL_NO_CHANS
    AUTH_CHPASS_BADPASS
    AUTH_CHPASS_SUCCESS
    AUTH_STATUS
    AUTH_USER_ADDED
    AUTH_MASK_ADDED
    AUTH_MASK_EXISTS
    AUTH_MASK_DELETED
    AUTH_USER_DELETED
    AUTH_USER_NOSUCH
    AUTH_USER_EXISTS
    AUTH_NOT_ENOUGH_ACCESS
  / ],
  
  INFO => [ qw/
    INFO_DONTKNOW
    INFO_WHAT
    INFO_TELL_WHO
    INFO_TELL_WHAT
    INFO_ADD
    INFO_DEL
    INFO_ABOUT
    INFO_REPLACE
    INFO_ERR_NOSUCH
    INFO_ERR_EXISTS
    INFO_BADSYNTAX_ADD
    INFO_BADSYNTAX_DEL
    INFO_BADSYNTAX_REPL
  / ],
  
  RDB => [ qw/
    RDB_ERR_NO_SUCH_RDB
    RDB_ERR_INVALID_NAME
    RDB_ERR_NO_SUCH_ITEM
    RDB_ERR_NO_STRING
    RDB_ERR_RDB_EXISTS
    RDB_ERR_NOTPERMITTED
    RDB_CREATED
    RDB_DELETED
    RDB_ITEM_ADDED
    RDB_ITEM_DELETED
    RDB_ITEM_INFO
    RDB_UNLINK_FAILED
  / ],
  
);

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

try {
  Bot::Cobalt::Lang->new(
    lang => 'somelang',
  );
} catch {
  pass("Died as expected in new()");
  0
} and fail("Should've died for insufficient args in new()");

my $langdir = File::Spec->catdir( $basedir, 'etc', 'langs' );

my $absolute = new_ok( 'Bot::Cobalt::Lang' => [
    lang => 'english',
    absolute_path => File::Spec->catfile( $langdir, 'english.yml' ),
  ],
);

ok(keys %{ $absolute->rpls }, 'absolute_path set has RPLs' );

my $coreset = new_ok( 'Bot::Cobalt::Lang' => [
    use_core => 1,
    
    lang => 'english',
    lang_dir => $langdir,
  ],
);

ok(keys %{ $coreset->rpls }, 'english set has RPLs' );

my $english = new_ok( 'Bot::Cobalt::Lang' => [
    lang => 'english',
    lang_dir => $langdir,
  ],
);

ok(keys %{ $english->rpls }, 'english set has RPLs' );

cmp_ok( $english->spec, '>=', 7 );

my $ebonics = new_ok( 'Bot::Cobalt::Lang' => [
    lang => 'ebonics',
    lang_dir => $langdir,
  ],
);

ok( keys %{ $ebonics->rpls }, 'ebonics set has RPLs' );

SET: for my $set (keys %sets) {
  RPL: for my $rpl (@{$sets{$set}}) {
    ok( $ebonics->rpls->{$rpl}, "Exists: $rpl" )
  }
}
