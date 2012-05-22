package Bot::Cobalt::Plugin::Master;
our $VERSION = '0.001';
## FIXME:
##  !server < list | connect | disconnect ... >
##  !restart(?) / !die

use 5.10.1;
use Bot::Cobalt;
use Bot::Cobalt::Common;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->plugin_register( $self, 'SERVER',
    [
      'public_cmd_join',
      'public_cmd_part',
      'public_cmd_cycle',

#      'public_cmd_server',
      'public_cmd_die',

      'public_cmd_op',
      'public_cmd_deop',
      'public_cmd_voice',
      'public_cmd_devoice',
    ],
  );

  $core->log->info("Loaded");  
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unloaded");
  return PLUGIN_EAT_NONE
}


### JOIN / PART / CYCLE

sub Bot_public_cmd_cycle {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${ $_[0] };
  my $context = $msg->context;
  my $src_nick = $msg->src_nick;

  my $pcfg = $core->get_plugin_cfg($self) || {};

  my $requiredlev = $pcfg->{Opts}->{Level_joinpart} // 3; 
  my $authed_lev  = $core->auth->level($context, $src_nick);
  
  ## fail quietly for unauthed users
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;

  $core->log->info("CYCLE issued by $src_nick");
  
  my $channel = $msg->channel;  
  broadcast( 'part', $context, $channel, "Cycling $channel" );
  broadcast( 'join', $context, $channel );

  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_join {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${ $_[0] };
  my $context  = $msg->context;
  my $src_nick = $msg->src_nick;

  my $pcfg = $core->get_plugin_cfg($self) || {};

  my $requiredlev = $pcfg->{Opts}->{Level_joinpart} // 3; 
  my $authed_lev  = $core->auth->level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;
  
  my $channel = $msg->message_array->[0];
  return PLUGIN_EAT_ALL unless $channel;
  
  $core->log->info("JOIN ($channel) issued by $src_nick");
  
  broadcast( 'message', $context, $msg->channel,
    "Joining $channel"
  );
  broadcast( 'join', $context, $channel );
  
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_part {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${ $_[0] };
  my $context  = $msg->context;
  my $src_nick = $msg->src_nick;

  my $pcfg = $core->get_plugin_cfg($self) || {};

  my $requiredlev = $pcfg->{Opts}->{Level_joinpart} // 3; 
  my $authed_lev  = $core->auth->level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;
  
  my $channel = $msg->message_array->[0] // $msg->channel;
  
  $core->log->info("PART ($channel) issued by $src_nick");
  
  broadcast( 'message', $context, $msg->channel,
      "Leaving $channel"
  );
  broadcast( 'part', $context, $channel, "Requested by $src_nick" );
  
  return PLUGIN_EAT_ALL
}


### OP / DEOP
sub Bot_public_cmd_op {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${ $_[0] };
  my $context  = $msg->context;
  my $src_nick = $msg->src_nick;

  my $pcfg = $core->get_plugin_cfg($self) || {};

  my $requiredlev = $pcfg->{Opts}->{Level_op} // 3;
  my $authed_lev  = $core->auth->level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;
  
  my $target_usr = $msg->message_array->[0] // $msg->src_nick;
  my $channel = $msg->channel;
  broadcast( 'mode', $context, $channel, "+o $target_usr" );
  
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_deop {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${ $_[0] };
  my $context  = $msg->context;
  my $src_nick = $msg->src_nick;

  my $pcfg = $core->get_plugin_cfg($self) || {};

  my $requiredlev = $pcfg->{Opts}->{Level_op} // 3;
  my $authed_lev  = $core->auth->level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;
  
  my $target_usr = $msg->message_array->[0] // $msg->src_nick;
  my $channel = $msg->channel;
  
  broadcast( 'mode', $context, $channel, "-o $target_usr" );
  
  return PLUGIN_EAT_ALL
}

## VOICE / DEVOICE

sub Bot_public_cmd_voice {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${ $_[0] };
  my $context  = $msg->context;
  my $src_nick = $msg->src_nick;

  my $pcfg = $core->get_plugin_cfg($self) || {};

  my $requiredlev = $pcfg->{Opts}->{Level_voice} // 2;
  my $authed_lev  = $core->auth->level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;
  
  my $target_usr = $msg->message_array->[0] // $msg->src_nick;
  my $channel = $msg->channel;
  
  broadcast( 'mode', $context, $channel, "+v $target_usr" );
  
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_devoice {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${ $_[0] };
  my $context  = $msg->context;
  my $src_nick = $msg->src_nick;

  my $pcfg = $core->get_plugin_cfg($self) || {};

  my $requiredlev = $pcfg->{Opts}->{Level_voice} // 2;
  my $authed_lev  = $core->auth->level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;
  
  my $target_usr = $msg->message_array->[0] // $msg->src_nick;
  my $channel = $msg->channel;
  
  broadcast( 'mode', $context, $channel, "-v $target_usr" );
  
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_die {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ $_[0] };
  
  my $context  = $msg->context;
  my $src_nick = $msg->src_nick;
  
  my $pcfg = $core->get_plugin_cfg($self) || {};
  
  my $requiredlev = $pcfg->{Opts}->{Level_die} // 9999;
  my $authed_lev  = $core->auth->level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;

  my $auth_usr = $core->auth->username($context, $src_nick);

  logger->warn("Shutdown requested; $src_nick ($auth_usr)");

  $core->shutdown;
}


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Plugin::Master - Basic bot master commands

=head1 SYNOPSIS

  !cycle
  !join <channel>
  !part [channel]
  
  !op   [nickname]
  !deop [nickname]
  
  !voice   [nickname]
  !devoice [nickname]

  !die

=head1 DESCRIPTION

This plugin provides basic bot/channel control commands.

Levels for each command are specified in C<plugins.conf>:

  ## Defaults:
  Module: Bot::Cobalt::Plugin::Master
  Opts:
    Level_die: 9999
    Level_server: 9999
    Level_joinpart: 3
    Level_voice: 2
    Level_op: 3

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
