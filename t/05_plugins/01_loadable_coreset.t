use Test::More tests => 48;
my @core;
BEGIN {
  my $prefix = 'Cobalt::Plugin::';
  @core = map { $prefix.$_ } qw/
    Alarmclock
    Auth
    Games
    Info3
    Master
    PluginMgr
    RDB
    Rehash
    Seen
    Version
    WWW
    
    Extras::Karma
    Extras::Money
    Extras::Relay
    Extras::Shorten
    Extras::TempConv
  /;

  use_ok($_) for @core;
}

new_ok($_) for @core;
can_ok($_, 'Cobalt_register', 'Cobalt_unregister') for @core;
