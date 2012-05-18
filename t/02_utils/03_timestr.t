use Test::More tests => 6;

## Bot::Cobalt::Utils tests

BEGIN {
  use_ok( 'Bot::Cobalt::Utils', qw/
    timestr_to_secs
    secs_to_timestr
  / );
}
ok( timestr_to_secs('120s') == 120, 'timestr_to_secs (120s)' );
ok( timestr_to_secs('10m') == 600, 'timestr_to_secs (10m)' );
ok( timestr_to_secs('2h10m8s') == 7808, 'timestr_to_secs (2h10m8s)' );
ok( secs_to_timestr(60) eq '1m', 'secs_to_timestr(60)' );
ok( secs_to_timestr(820) eq '13m40s', 'secs_to_timestr (820)' );
