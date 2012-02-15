package Cobalt::Plugin::Extras::Relay;
our $VERSION = '0.002';

## Simplistic relaybot plugin

use Cobalt::Common;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  my $pcfg = $core->get_plugin_cfg($self);
  my $relays = $pcfg->{Relays};
  unless ($relays and ref $relays eq 'ARRAY') {
    $core->log->warn("'Relays' conf directive not valid, should be a list");
  } else {
    for my $ref (@$relays) {
      my $from = $ref->{From} // next;
      my $to   = $ref->{To}   // next;
      my $context0 = $from->{Context};
      my $channel0 = $from->{Channel};
      my $context1 = $to->{Context};
      my $channel1 = $to->{Channel};
      
      $self->{Relays}->{$context0}->{$channel0} = [ $context1, $channel1 ];
      $self->{Relays}->{$context1}->{$channel1} = [ $context0, $channel0 ];
      
      $core->log->debug(
        "relaying: $context0 $channel0 -> $context1 $channel1"
      );
    }
  }

  $core->plugin_register( $self, 'SERVER',
    [
      'public_msg',
      'ctcp_action',
      'public_cmd_relay',
      'public_cmd_rwhois',
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

sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };

  my $channel = $msg->{target};

  return PLUGIN_EAT_NONE
    unless $self->{Relays}->{$context}->{$channel};

  my $src_nick = $msg->{src_nick};

  my $to_context = $self->{Relays}->{$context}->{$channel}[0];
  my $to_channel = $self->{Relays}->{$context}->{$channel}[1];
  
  ## should be good to relay away ...
  my $text = $msg->{orig};
  my $str  = "<${src_nick}:${channel}> $text";
  $core->send_event( 'send_message',
    $to_context,
    $to_channel,
    $str
  );
  
  return PLUGIN_EAT_NONE
}

sub Bot_ctcp_action {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $action  = ${ $_[1] };
  
  my $channel = $action->{target};
  return PLUGIN_EAT_NONE
    unless $self->{Relays}->{$context}->{$channel};

  my $src_nick = $action->{src_nick};

  my $to_context = $self->{Relays}->{$context}->{$channel}[0];
  my $to_channel = $self->{Relays}->{$context}->{$channel}[1];
  
  my $text = $action->{orig};
  my $str  = "<action:${channel}> * $src_nick $text";
  $core->send_event( 'send_message',
    $to_context,
    $to_channel,
    $str
  );

  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_relay {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };
  ## Show relay info
  
  my $channel = $msg->{target};
  
  my $resp;
  if ($self->{Relays}->{$context}->{$channel}) {

    my $to_context = $self->{Relays}->{$context}->{$channel}[0];
    my $to_channel = $self->{Relays}->{$context}->{$channel}[1];

    $resp = "Currently relaying to $to_channel on context $to_context";

    SERVINFO: unless ( $core->get_irc_server($to_context) ) {
      $resp .= "; remote end appears to be missing!"
    } else {
      my $irc = $core->get_irc_obj($to_context) || last SERVINFO;
      my $servername = $irc->server_name;
      $resp .= "; remote end: $servername";
    }

  } else {
    $resp = "There are no relays for $channel on context $context";
  }
  
  $core->send_event( 'send_message', $context, $channel, $resp );
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_rwhois {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };

  my $channel = $msg->{target};

  my $remoteuser = $msg->{message_array}[0];

  return PLUGIN_EAT_ALL unless $remoteuser;

  my $resp;
  RWHOIS: if ($self->{Relays}->{$context}->{$channel}) {
    my $to_context = $self->{Relays}->{$context}->{$channel}[0];
    my $irc = $core->get_irc_obj($to_context) || last RWHOIS;
    my $nickinfo = $irc->nick_info($remoteuser);
    
    unless ($nickinfo) {
      $resp = "No such user: $remoteuser";
    } else {
      my $nick = $nickinfo->{Nick};
      my $user = $nickinfo->{User};
      my $host = $nickinfo->{Host};
      my $real = $nickinfo->{Real};
      my $userhost = "${nick}!${user}\@${host}";
      $resp = "$remoteuser ($userhost) [$real]"
    }
  }
  
  $resp = "There are no relays for $channel on context $channel"
    unless $resp;
  $core->send_event( 'send_message', $context, $channel, $resp );
  
  return PLUGIN_EAT_ALL
}

1;
__END__

=pod

=head1 NAME

Cobalt::Plugin::Extras::Relay - simplistic bidirectional IRC relay

=head1 DESCRIPTION

This is a simplistic plugin providing bi-directional relay.

As of this writing, it doesn't know how to multiplex -- you can only 
relay between a pair of channels (on the same or different networks).

... patches welcome, of course :-)

=head1 CONFIGURATION

An example relay.conf:

  Relays:
    - From:
        Context: Main
        Channel: '#otw'
      To:
        Context: IRCNode
        Channel: '#otw'
    - From:
        Context: Main
        Channel: '#unix'
      To:
        Context: Paradox
        Channel: '#perl'

See etc/plugins/relay.conf in the core Cobalt2 distribution.

=head1 COMMANDS

=head2 !relay

Display the configured relay for the current channel.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
