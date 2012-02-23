package Cobalt::Plugin::Master;
our $VERSION = '0.01';
##  !die / !restart
##  !join / !part / !cycle
## FIXME:
##  !server < list | connect | disconnect ... >
##  !restart(?) / !die

use Cobalt::Common;

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
#      'public_cmd_die',
#      'public_cmd_restart',

      'public_cmd_op',
      'public_cmd_deop',
      'public_cmd_voice',
      'public_cmd_devoice',
    ],
  );

  $core->log->info("$VERSION loaded");  
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
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };
  my $src_nick = $msg->{src_nick};

  my $pcfg = $core->get_plugin_cfg || {};

  my $requiredlev = $pcfg->{Opts}->{Level_joinpart} // 3; 
  my $authed_lev  = $core->auth_level($context, $src_nick);
  
  ## fail quietly for unauthed users
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;

  $core->log->info("CYCLE issued by $src_nick");
  
  my $channel = $msg->{channel};  
  $core->send_event( 'part', $context, $channel );
  $core->send_event( 'join', $context, $channel );

  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_join {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };
  my $src_nick = $msg->{src_nick};

  my $pcfg = $core->get_plugin_cfg || {};

  my $requiredlev = $pcfg->{Opts}->{Level_joinpart} // 3; 
  my $authed_lev  = $core->auth_level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;
  
  my $channel = $msg->{message_array}->[0];
  return PLUGIN_EAT_ALL unless $channel;
  
  $core->log->info("JOIN ($channel) issued by $src_nick");
  
  $core->send_event( 'send_message', $context, $msg->{channel},
    "Joining $channel"
  );
  $core->send_event( 'join', $context, $channel );
  
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_part {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };
  my $src_nick = $msg->{src_nick};

  my $pcfg = $core->get_plugin_cfg || {};

  my $requiredlev = $pcfg->{Opts}->{Level_joinpart} // 3; 
  my $authed_lev  = $core->auth_level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;
  
  my $channel = $msg->{message_array}->[0] // $msg->{channel};
  
  my $irc = $core->get_irc_obj($context);
  unless ($irc->channels->{$channel}) {
    $core->send_event( 'send_message', $context, $msg->{channel},
      "Not currently on $channel"
    );
    return PLUGIN_EAT_ALL
  }
  
  $core->log->info("PART ($channel) issued by $src_nick");
  
  $core->send_event( 'send_message', $context, $msg->{channel},
    "Leaving $channel"
  );
  $core->send_event( 'part', $context, $channel );
  
  return PLUGIN_EAT_ALL
}


### OP / DEOP
sub Bot_public_cmd_op {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };
  my $src_nick = $msg->{src_nick};

  my $pcfg = $core->get_plugin_cfg || {};

  my $requiredlev = $pcfg->{Opts}->{Level_op} // 3;
  my $authed_lev  = $core->auth_level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;
  
  my $target_usr = $msg->{message_array}->[0] // $msg->{src_nick};
  my $channel = $msg->{channel};
  $core->send_event( 'mode', $context, $channel, "+o $target_usr" );
  
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_deop {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };
  my $src_nick = $msg->{src_nick};

  my $pcfg = $core->get_plugin_cfg || {};

  my $requiredlev = $pcfg->{Opts}->{Level_op} // 3;
  my $authed_lev  = $core->auth_level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;
  
  my $target_usr = $msg->{message_array}->[0] // $msg->{src_nick};
  my $channel = $msg->{channel};
  
  $core->send_event( 'mode', $context, $channel, "-o $target_usr" );
  
  return PLUGIN_EAT_ALL
}

## VOICE / DEVOICE

sub Bot_public_cmd_voice {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };
  my $src_nick = $msg->{src_nick};

  my $pcfg = $core->get_plugin_cfg || {};

  my $requiredlev = $pcfg->{Opts}->{Level_voice} // 2;
  my $authed_lev  = $core->auth_level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;
  
  my $target_usr = $msg->{message_array}->[0] // $msg->{src_nick};
  my $channel = $msg->{channel};
  
  $core->send_event( 'mode', $context, $channel, "+v $target_usr" );
  
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_devoice {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };
  my $src_nick = $msg->{src_nick};

  my $pcfg = $core->get_plugin_cfg || {};

  my $requiredlev = $pcfg->{Opts}->{Level_voice} // 2;
  my $authed_lev  = $core->auth_level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;
  
  my $target_usr = $msg->{message_array}->[0] // $msg->{src_nick};
  my $channel = $msg->{channel};
  
  $core->send_event( 'mode', $context, $channel, "-v $target_usr" );
  
  return PLUGIN_EAT_ALL
}


1;
__END__
