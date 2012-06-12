package Bot::Cobalt::IRC::Role::AdminCmds;
our $VERSION;

use 5.12.1;
use Moo::Role;
use strictures 1;

use Bot::Cobalt;
use Bot::Cobalt::Common;


sub Bot_public_cmd_server {
  my ($self, $core) = splice @_, 0, 2;
  
  my $msg = ${ $_[0] };
  
  my $context  = $msg->context;
  my $src_nick = $msg->src_nick;
  
  my $auth_flags = $core->auth->flags($context, $src_nick);
  
  return PLUGIN_EAT_ALL unless $auth_flags->{SUPERUSER};
  
  my $cmd = lc($msg->message_array->[0] || 'list');
  
  my $meth = '_cmd_'.$cmd;
  
  unless ( $self->can($meth) ) {
    broadcast( 'message',
      $msg->context,
      $msg->channel,
      "Unknown command; try one of: list, current, connect, disconnect"
    );
  
    return PLUGIN_EAT_ALL
  }
  
  $self->$meth($msg)
}

sub _cmd_list {
  my ($self, $msg) = @_;
  
  my @contexts = keys %{ core->Servers };
  
  broadcast( 'message',
    $msg->context,
    $msg->channel,
    "Active contexts: ".join ' ', @contexts
  );
  
  return PLUGIN_EAT_ALL
}

sub _cmd_current {
  my ($self, $msg) = @_;

  broadcast( 'message',
    $msg->context,
    $msg->channel,
    "Currently on context ".$msg->context
  );

  return PLUGIN_EAT_ALL
}

sub _cmd_connect {
  my ($self, $msg) = @_;
  
  my $pcfg = plugin_cfg($self);
  
  unless (ref $pcfg eq 'HASH' && keys %$pcfg) {
    broadcast( 'message',
      "Could not locate any network configuration."
    );
    
    return PLUGIN_EAT_ALL
  }
  
  my $target_ctxt = $msg->message_array->[1];
  
  unless (defined $target_ctxt) {
    broadcast( 'message',
      $msg->context,
      $msg->channel,
      "No context specified."
    );
    
    return PLUGIN_EAT_ALL
  }
  
  unless ($pcfg->{$target_ctxt}) {
    broadcast( 'message',
      $msg->context,
      $msg->channel,
      "Could not locate configuration for context $target_ctxt"
    );
  
    return PLUGIN_EAT_ALL
  }
  
  ## Do we alraedy have this context?
  if (my $ctxt_obj = irc_context($target_ctxt) ) {
  
    if ($txt_obj->connected) {
    
      ## FIXME
      ## Issue affirmative message
      ## Clean up this context and try to reconnect
      ## Set a timer to run retries
      
      return PLUGIN_EAT_ALL
    }    
  }

  broadcast( 'message',
    $msg->context,
    $msg->channel,
    "Issuing connect for context $target_ctxt"
  );
    
  broadcast( 'ircplug_connect', $target_ctxt );
    
  return PLUGIN_EAT_ALL  
}

sub _cmd_disconnect {
  my ($self, $msg) = @_;
  
  my $target_ctxt = $msg->message_array->[1];
  
  unless (defined $target_ctxt) {
    broadcast( 'message',
      $msg->context,
      $msg->channel,
      "No context specified."
    );
  
    return PLUGIN_EAT_ALL
  }
  
  my $ctxt_obj;
  unless ($ctxt_obj = irc_context($target_ctxt) ) {
    broadcast( 'message',
      $msg->context,
      $msg->channel,
      "Could not find context object for $target_ctxt"
    );
  
    return PLUGIN_EAT_ALL
  }

  unless (keys %{ core->Servers } > 1) {
    broadcast( 'message',
      $msg->context,
      $msg->channel,
      "Refusing disconnect; have no other active contexts."
    );
  
    return PLUGIN_EAT_ALL
  }
  
  broadcast( 'message',
    $msg->context,
    $msg->channel,
    "Attempting to disconnect from $target_ctxt"
  );
  
  broadcast( 'ircplug_disconnect', $context );
  
  return PLUGIN_EAT_ALL
}


1
## FIXME POD
