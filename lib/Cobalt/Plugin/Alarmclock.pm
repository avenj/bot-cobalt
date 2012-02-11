package Cobalt::Plugin::Alarmclock;
our $VERSION = '0.12';

use 5.12.1;
use strict;
use warnings;

use Cobalt::Utils qw/ timestr_to_secs rplprintf /;

use Object::Pluggable::Constants qw/ :ALL /;

## Commands:
##  !alarmclock

sub new { bless ( {}, shift ); }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  $core->plugin_register($self, 'SERVER', 
    [ 'public_cmd_alarmclock' ] 
  );

  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
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
  my $cfg = $core->get_plugin_cfg( $self );
  my $minlevel = $cfg->{PluginOpts}->{LevelRequired} // 1;

  ## quietly do nothing for unauthorized users
  return PLUGIN_EAT_NONE 
    unless $core->auth_level($context, $setter) >= $minlevel;

  ## This is the array of (format-stripped) args to the _public_cmd_
  my @args = @{ $msg->{message_array} };  
  ## -> f.ex.:  split ' ', !alarmclock 1h10m things and stuff
  my $timestr = shift @args;
  ## the rest of this string is the alarm text:
  my $txtstr  = join ' ', @args;

  $txtstr = "$setter: ALARMCLOCK: ".$txtstr ;

  ## set a timer
  my $secs = timestr_to_secs($timestr) || 1;
  my $channel = $msg->{channel};

  my $id = $core->timer_set( $secs,
    {
      Type => 'msg',
      Context => $context,
      Target => $channel,
      Text => $txtstr,
    }
  );

  if ($id) {
    $resp = rplprintf( $core->lang->{ALARMCLOCK_SET},
      {
        nick => $setter,
        secs => $secs,
        timerid => $id,
        timestr => $timestr,
      }
    );
  } else {
    $resp = rplprintf( $core->lang->{RPL_TIMER_ERR} );
  }

  if ($resp) {
    my $target = $msg->{channel};
    $core->send_event( 'send_message', $context, $target, $resp );
  }

  return PLUGIN_EAT_ALL
}

1;
