package Cobalt::Plugin::Alarmclock;

use 5.12.1;
use strict;
use warnings;

use Cobalt::Utils qw/ timestr_to_secs /;

use Object::Pluggable::Constants qw/ :ALL /;

## Commands:
##  Bot_cmd_alarmclock

sub new { bless ( {}, shift ); }

sub Cobalt_register {
  my ($self, $core) = @_;

  ## register for public_cmd_alarmclock:
  $core->plugin_register($self, 'SERVER', 
    [ 'public_cmd_alarmclock' ] 
  );

  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  $core->log->info("Unregistering core IRC plugin");
  return PLUGIN_EAT_NONE
}


sub Bot_public_cmd_alarmclock {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};

  my $me = $msg->{myself};

  my $resp;

  my $setter = $msg->{src_nick};

  my $pkg = __PACKAGE__;
  my $cfg = $core->cfg->{plugin_cf}->{$pkg};
  my $minlevel = $cfg->{PluginOpts}->{Level} // 1;
  ## FIXME: auth check

  ## This is the array of (format-stripped) args to the _public_cmd_
  my @args = @{ $msg->{message_array} };  
  ## E.g.:
  ##  !alarmclock 1h10m things and stuff
  my $timestr = shift @args;
  ## the rest of this string is the alarm text:
  my $txtstr  = join ' ', @args;

  ## FIXME: set a Timer
  ## generic interface for this?

  ## FIXME: send a response
  if ($resp) {
    my $target = $msg->{channel};
    $core->send_event( 'send_message', $context, $target, $resp );
  }

  return PLUGIN_EAT_NONE
}

1;
