package Bot::Cobalt::Plugin::Master;
our $VERSION = '0.008_01';

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

      'public_cmd_server',
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

  my $requiredlev = $pcfg->{PluginOpts}->{Level_joinpart} // 3; 
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

  my $requiredlev = $pcfg->{PluginOpts}->{Level_joinpart} // 3; 
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

  my $requiredlev = $pcfg->{PluginOpts}->{Level_joinpart} // 3; 
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

  my $requiredlev = $pcfg->{PluginOpts}->{Level_op} // 3;
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

  my $requiredlev = $pcfg->{PluginOpts}->{Level_op} // 3;
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

  my $requiredlev = $pcfg->{PluginOpts}->{Level_voice} // 2;
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

  my $requiredlev = $pcfg->{PluginOpts}->{Level_voice} // 2;
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
  
  my $requiredlev = $pcfg->{PluginOpts}->{Level_die} || 9999;
  my $authed_lev  = $core->auth->level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;

  my $auth_usr = $core->auth->username($context, $src_nick);

  logger->warn("Shutdown requested; $src_nick ($auth_usr)");

  $core->shutdown;
}

sub Bot_public_cmd_server {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ $_[0] };
  
  my $context  = $msg->context;
  my $src_nick = $msg->src_nick,
  
  my $pcfg = $core->get_plugin_cfg($self) || {};
  
  my $requiredlev = $pcfg->{PluginOpts}->{Level_server} || 9999;
  my $authed_lev  = $core->auth->level($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $authed_lev >= $requiredlev;
  
  my $cmd = lc($msg->message_array->[0] || 'list') ;

  CMD: {
  
    if ($cmd eq "list") {
      my @contexts = keys %{ $core->Servers };
      
      broadcast( 'message', $context, $msg->channel,
        "Active contexts: ".join ' ', @contexts
      );
      
      ## FIXME
      ## No real convenient way to get a list of non-enabled contexts..
      ##  ... maybe this whole mess really belongs in IRC.pm ?
    
      return PLUGIN_EAT_ALL
    }
    
    if ($cmd eq "current") {
      broadcast( 'message', $context, $msg->channel,
        "Currently on server context $context"
      );

      return PLUGIN_EAT_ALL
    }
    
    if ($cmd eq "connect") {
      my $irc_pcfg = $core->get_plugin_cfg('IRC');
      unless (ref $irc_pcfg eq 'HASH' && keys %$irc_pcfg) {
        broadcast( 'message', $context, $msg->channel,
          "Could not locate cfg for IRC plugin"
        );
        
        return PLUGIN_EAT_ALL
      }
      
      my $target_ctxt = $msg->message_array->[1];
      
      unless (defined $target_ctxt) {
        broadcast( 'message', $context, $msg->channel,
          "No context specified."
        );
        
        return PLUGIN_EAT_ALL
      }
      
      unless ($irc_pcfg->{$target_ctxt}) {
        broadcast( 'message', $context, $msg->channel,
          "Could not locate cfg for context $target_ctxt"
        );
      
        return PLUGIN_EAT_ALL
      }
      
      if (my $ctxt_obj = $core->get_irc_context($target_ctxt)) {
        if ($ctxt_obj->connected) {
          broadcast('message', $context, $msg->channel,
            "Context $target_ctxt claims to be currently connected."
          );
          
          return PLUGIN_EAT_ALL
        }
      }
      
      broadcast( 'message', $context, $msg->channel,
        "Issuing connect for context $target_ctxt"
      );
      
      broadcast( 'ircplug_connect', $target_ctxt );

      return PLUGIN_EAT_ALL
    }
    
    if ($cmd eq "disconnect") {
      ## FIXME if this is our only context, refuse
      
      my $target_ctxt = $msg->message_array->[1];
      
      unless (defined $target_ctxt) {
        broadcast( 'message', $context, $msg->channel,
          "No context specified."
        );
        
        return PLUGIN_EAT_ALL
      }
      
      my $ctxt_obj;
      unless ($ctxt_obj = $core->get_irc_context($target_ctxt)) {
        broadcast( 'message', $context, $msg->channel,
          "Could not find context object for $target_ctxt"
        );
        
        return PLUGIN_EAT_ALL
      }
      
      unless ($ctxt_obj->connected) {
        broadcast( 'message', $context, $msg->channel,
          "Context $target_ctxt claims to not be currently connected."
        );
        
        return PLUGIN_EAT_ALL
      }
      
      unless (keys %{ $core->Servers } > 1) {
        broadcast( 'message', $context, $msg->channel,
          "Cannot disconnect; have no other active contexts."
        );
      
        return PLUGIN_EAT_ALL
      }

      broadcast( 'message', $context, $msg->channel,
        "Attempting to disconnect from context $target_ctxt"
      ); 
      
      broadcast( 'ircplug_disconnect', $context );
    
      return PLUGIN_EAT_ALL
    }
    
    ## Fell through
    broadcast( 'message', $msg->context, $msg->channel,
      "Unknown command; try one of: list, current, connect, disconnect"
    );

    return PLUGIN_EAT_ALL
  }

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
