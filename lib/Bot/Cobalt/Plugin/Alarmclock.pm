package Bot::Cobalt::Plugin::Alarmclock;
our $VERSION = '0.006';

use 5.10.1;
use strict;
use warnings;

use Bot::Cobalt;

use Bot::Cobalt::Utils qw/ timestr_to_secs rplprintf /;

use Object::Pluggable::Constants qw/ :ALL /;

## Commands:
##  !alarmclock

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  ## {Active}->{$timerid} = [ $context, $username ]
  $self->{Active} = {};

  register($self, 'SERVER', 
    [ 
      'public_cmd_alarmclock',
      'public_cmd_alarmdelete',
      'public_cmd_alarmdel',
      'executed_timer',
    ] 
  );

  $core->log->info("Loaded alarm clock");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistering core IRC plugin");
  $core->timer_del_alias( $core->get_plugin_alias($self) );
  return PLUGIN_EAT_NONE
}

sub Bot_deleted_timer { Bot_executed_timer(@_) }
sub Bot_executed_timer {
  my ($self, $core) = splice @_, 0, 2;
  my $timerid = ${$_[0]};
  return PLUGIN_EAT_NONE
    unless exists $self->{Active}->{$timerid};
  
  $core->log->debug("clearing timer state for $timerid")
    if $core->debug > 1;  
  delete $self->{Active}->{$timerid};
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_alarmdelete { Bot_public_cmd_alarmdel(@_) }

sub Bot_public_cmd_alarmdel {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${$_[0]};

  my $context = $msg->context;
  my $nick    = $msg->src_nick;
  
  my $auth_usr = $core->auth->username($context, $nick);
  return PLUGIN_EAT_NONE unless $auth_usr;

  my $msg_arr = $msg->message_array;
  my $timerid = $msg_arr->[0];
  return PLUGIN_EAT_ALL unless $timerid;
  
  my $channel = $msg->channel;
  
  unless (exists $self->{Active}->{$timerid}) {
    broadcast( 'message', $context, $channel,
      rplprintf( $core->lang->{ALARMCLOCK_NOSUCH},
        { nick => $nick, timerid => $timerid },
      )
    );
    return PLUGIN_EAT_ALL
  }
  
  my $thistimer = $self->{Active}->{$timerid};
  my ($ctxt_set, $ctxt_by) = @$thistimer;
  unless ($ctxt_set eq $context && $auth_usr eq $ctxt_by) {
    my $auth_lev = $core->auth->level($context, $nick);
    ## superusers can override:
    unless ($auth_lev == 9999) {
      broadcast( 'message', $context, $channel,
        rplprintf( $core->lang->{ALARMCLOCK_NOTYOURS},
          { nick => $nick, timerid => $timerid },
        )
      );
      return PLUGIN_EAT_ALL
    }
  }
  
  $core->timer_del($timerid);
  delete $self->{Active}->{$timerid};
  
  broadcast( 'message', $context, $channel,
    rplprintf( $core->lang->{ALARMCLOCK_DELETED},
      { nick => $nick, timerid => $timerid },
    )
  );
  return PLUGIN_EAT_ALL
}


sub Bot_public_cmd_alarmclock {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${$_[0]};
  
  my $context = $msg->context;
  my $setter  = $msg->src_nick;

  my $cfg = $core->get_plugin_cfg( $self );
  my $minlevel = $cfg->{PluginOpts}->{LevelRequired} // 1;

  ## quietly do nothing for unauthorized users
  return PLUGIN_EAT_NONE 
    unless $core->auth->level($context, $setter) >= $minlevel;
  my $auth_usr = $core->auth->username($context, $setter);

  ## This is the array of (format-stripped) args to the _public_cmd_
  my $args = $msg->message_array;
  ## -> f.ex.:  split ' ', !alarmclock 1h10m things and stuff
  my $timestr = shift @$args;
  ## the rest of this string is the alarm text:
  my $txtstr  = join ' ', @$args;

  $txtstr = "$setter: ALARMCLOCK: ".$txtstr ;

  ## set a timer
  my $secs = timestr_to_secs($timestr) || 1;
  my $channel = $msg->channel;

  my $id = $core->timer_set( $secs,
    {
      Type => 'msg',
      Context => $context,
      Target => $channel,
      Text   => $txtstr,
      Alias  => $core->get_plugin_alias($self),
    }
  );

  my $resp;
  if ($id) {
    $self->{Active}->{$id} = [ $context, $auth_usr ];
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
    broadcast( 'message', $context, $channel, $resp );
  }

  return PLUGIN_EAT_ALL
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Plugin::Alarmclock - Timed IRC highlights

=head1 SYNOPSIS

  !alarmclock 20m go do some something
  !alarmclock 1h30m stop staring at irc

=head1 DESCRIPTION

This plugin allows authorized users to set a time via either a time string 
(see L<Bot::Cobalt::Utils/"timestr_to_secs">) or a specified number of seconds.

When the timer expires, the bot will highlight the user's nickname and 
display the specified string in the channel in which the alarmclock was set.

For example:

  !alarmclock 5m check my laundry
  !alarmclock 2h15m10s remind me in 2 hours 15 mins 10 secs

(Accuracy down to the second is not guaranteed. Plus, this is IRC. Sorry.)

Mimics B<darkbot6> behavior, but with saner time string grammar.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
