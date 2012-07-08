use Test::More tests => 60;
my @core;
BEGIN {
  my $prefix = 'Bot::Cobalt::Plugin::';
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
    
    Extras::CPAN
    Extras::DNS
    Extras::Karma
    Extras::Money
    Extras::Relay
    Extras::Shorten
    Extras::TempConv
    
    OutputFilters::StripColor
    OutputFilters::StripFormat
  /;

  use_ok($_) for @core;
}

new_ok($_) for @core;
can_ok($_, 'Cobalt_register', 'Cobalt_unregister') for @core;

## FIXME
## instance a Bot::Cobalt::Core w/ tempdir path for var/
## issue a plugin_add for each
## pocoirc t/ has some helpful hints
