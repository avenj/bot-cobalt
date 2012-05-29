use Test::More tests => 8;

## Bot::Cobalt::Utils tests

BEGIN {
  use_ok( 'Bot::Cobalt::Utils', qw/
    timestr_to_secs
    secs_to_timestr
    secs_to_str
  / );
}

is( timestr_to_secs('120s'), 120, 'timestr_to_secs (120s)' );

is( timestr_to_secs('10m'), 600, 'timestr_to_secs (10m)' );

is( timestr_to_secs('1d'), 86400, 'timestr_to_secs (1d)' );

is( timestr_to_secs('2h10m8s'), 7808, 'timestr_to_secs (2h10m8s)' );

is( secs_to_timestr(60), '1m', 'secs_to_timestr(60)' );

is( secs_to_timestr(820), '13m40s', 'secs_to_timestr (820)' );

is( secs_to_str(600), '0 days, 00:10:00', 'secs_to_str (600)' );
