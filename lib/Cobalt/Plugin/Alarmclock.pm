package Cobalt::Plugin::Alarmclock;
our $VERSION = '0.10';

use 5.12.1;
use strict;
use warnings;

use Cobalt::Utils qw/ timestr_to_secs rplprintf /;

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
  my $cfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $minlevel = $cfg->{PluginOpts}->{LevelRequired} // 1;

  ## Quietly do nothing for unauthorized users
  return PLUGIN_EAT_NONE 
    unless ( $core->auth_level($context, $setter) >= $minlevel);

  ## This is the array of (format-stripped) args to the _public_cmd_
  my @args = @{ $msg->{message_array} };  
  ## E.g.:
  ##  !alarmclock 1h10m things and stuff
  my $timestr = shift @args;
  ## the rest of this string is the alarm text:
  my $txtstr  = join ' ', @args;

  $txtstr = "$setter: ALARMCLOCK: ".$txtstr ;

  ## set a timer
  my $secs = timestr_to_secs($timestr) || 1;
  my $channel = $msg->{channel};

  $core->timer_set( $secs,
    {
      Type => 'msg',
      Context => $context,
      Target => $channel,
      Text => $txtstr,
    }
  );

  $resp = rplprintf( $core->lang->{ALARMCLOCK_SET},
    {
      nick => $setter,
      secs => $secs,
      timestr => $timestr,
    }
  );

  if ($resp) {
    my $target = $msg->{channel};
    $core->send_event( 'send_message', $context, $target, $resp );
  }

  return PLUGIN_EAT_NONE
}

1;
