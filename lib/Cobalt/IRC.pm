package Cobalt::IRC;

## Core IRC plugin
## (server context 'Main')

=pod

=head1 NAME

Cobalt::IRC

=head1 Emitted Events

 Bot_connected
 Bot_disconnected
 Bot_server_error

 Bot_chan_sync

 Bot_public_msg
 Bot_private_msg
 Bot_notice

 Bot_user_kicked

=cut

use 5.12.1;
use strict;
use warnings;
use Carp;

use Moose;

use Object::Pluggable::Constants qw( :ALL );

use POE;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::CTCP;
use POE::Component::IRC::Plugin::AutoJoin;
use POE::Component::IRC::Plugin::Connector;
use POE::Component::IRC::Plugin::NickServID;
use POE::Component::IRC::Plugin::NickReclaim;

use IRC::Utils
  qw/parse_user uc_irc lc_irc strip_color strip_formatting/;

use namespace::autoclean;

has 'core' => (
  is => 'rw',
  isa => 'Object',
);

has 'irc' => (
  is => 'rw',
  isa => 'Object',
);


sub Cobalt_register {
  my ($self, $core) = @_;

  $self->core($core);

  ## register for events
  $core->plugin_register($self, 'SERVER',
    [ 'all' ],
  );

  $core->log->info(__PACKAGE__." registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  $core->log->info("Unregistering core IRC plugin");
  return PLUGIN_EAT_NONE
}

sub Bot_plugins_initialized {
  my ($self, $core) = splice @_, 0, 2;
  ## wait until plugins are all loaded, start IRC session
  $self->_start_irc();
  return PLUGIN_EAT_NONE
}

sub _start_irc {
  my ($self) = @_;
  my $cfg = $self->core->cfg->{core};

  my $server = $cfg->{IRC}->{ServerAddr} // 'irc.cobaltirc.org' ;
  my $port   = $cfg->{IRC}->{ServerPort} // 6667 ;

  my $nick = $cfg->{IRC}->{Nickname} // 'Cobalt' ;

  my $usessl = $cfg->{IRC}->{UseSSL} ? 1 : 0 ;
  my $use_v6 = $cfg->{IRC}->{IPv6} ? 1 : 0 ;

  $self->core->log->info("Spawning IRC, server: ($nick) $server $port");

  my $i = POE::Component::IRC::State->spawn(
    nick     => $nick,
    username => $cfg->{IRC}->{Username} || 'cobalt',
    ircname  => $cfg->{IRC}->{Realname}  || 'http://cobaltirc.org',
    server   => $server,
    port     => $port,
    useipv6  => $use_v6,
    raw => 0,
  ) or $self->core->log->emerg("poco-irc error: $!");

  ## add 'Main' to Servers
  $self->core->Servers->{Main} = {
    Name => $server,
    PreferredNick => $nick,
    Object => $i,
    Connected => 0,
    ConnectedAt => time(),
  };

  $self->irc($i);

  POE::Session->create(
    object_states => [
      $self => [
        '_start',

        'irc_connected',
        'irc_disconnected',
        'irc_error',

        'irc_chan_sync',

        'irc_public',
        'irc_msg',
        'irc_notice',
        'irc_ctcp_action',

        'irc_kick',
        'irc_mode',
        'irc_topic',

        'irc_nick',
        'irc_join',
        'irc_part',
        'irc_quit',
      ],
    ],
  );

  $self->core->log->debug("IRC Session created");
}


 ### IRC EVENTS ###

sub _start {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my $cfg = $self->core->cfg->{core};

  $self->core->log->debug("pocoirc plugin load");

  $self->irc->plugin_add('Connector' =>
    POE::Component::IRC::Plugin::Connector->new);
# FIXME make reclaim time configurable:
  $self->irc->plugin_add('NickReclaim' =>
    POE::Component::IRC::Plugin::NickReclaim->new(
        poll => $cfg->{Opts}->{NickRegainDelay} // 30,
      ), 
    );

  if ($cfg->{Opts}->{NickServPass}) {
    $self->irc->plugin_add('NickServID' =>
      POE::Component::IRC::Plugin::NickServID->new(
        Password => $cfg->{Opts}->{NickServPass},
      ),
    );
  }

  ## the single-server plugin just grabs Main context from channels cf:
  my $chanhash = $self->core->cfg->{channels}->{Main} // {} ;

  $self->irc->plugin_add('AutoJoin' =>
    POE::Component::IRC::Plugin::AutoJoin->new(
      Channels => [ keys %$chanhash ],
      RejoinOnKick => 1,
      Rejoin_delay => 5,  ## FIXME: configurables
      NickServ_delay => 1,
      Retry_when_banned => 60,
    ),
  );
  $self->irc->plugin_add('CTCP' =>
    POE::Component::IRC::Plugin::CTCP->new(
      version => "cobalt ".$self->core->version." (perl $^V)",
      userinfo => __PACKAGE__,
    ),
  );

  $self->irc->yield(register => 'all');
  $self->core->log->debug("pocoirc connect issued");

  my $opts = { };

  my $localaddr = $cfg->{IRC}->{BindAddr} // 0;
  $opts->{localaddr} = $localaddr if $localaddr;

  my $server_pass = $cfg->{IRC}->{ServerPass} // 0;
  $opts->{password} = $server_pass if $server_pass;

  $self->irc->yield(connect => $opts);
}

sub irc_chan_sync {
  my ($self, $chan) = @_[OBJECT, ARG0];

  my $resp = sprintf( $self->core->lang->{RPL_CHAN_SYNC}, $chan );

  ## issue Bot_chan_sync
  $self->core->send_event( 'chan_sync', $chan );

  $self->irc->yield(privmsg => $chan => $resp)
    if $self->core->cfg->{core}->{Opts}->{NotifyOnSync};
}

sub irc_public {
  my ($self, $kernel, $src, $where, $txt) = @_[OBJECT, KERNEL, ARG0 .. ARG2];
  my $me = $self->irc->nick_name();
  $txt = strip_color( strip_formatting($txt) );
  my ($nick, $user, $host) = parse_user($src);
  my $channel = $where->[0];

  ## create a msg packet and send_event to self->core

  my $msg = {
    context => 'Main',  # server context
    myself => $me,      # bot's current nickname
    src => $src,        # full Nick!User@Host
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    channel => $channel,  # first dest. channel seen
    target_array => $where,
    highlight => 0,
    cmdprefix => 0,
    message => $txt,
  };

  ## flag messages seemingly directed at the bot
  ## makes life easier for plugins
  $msg->{highlight} = 1 if $txt =~ /^${me}.?\s+/i;

  ## flag messages prefixed by cmdchar
  my $cmdchar = $self->core->cfg->{core}->{Opts}->{CmdChar} // '!';
  if ( $txt =~ /^${cmdchar}([^\s]+)/ ) {
    $msg->{cmdprefix} = 1;
    $msg->{cmd} = $1;
    ## issue a public_cmd_$cmd event to plugins
    ## command-only plugins can choose to only receive specified events
    $self->core->send_event( 
      'public_cmd_'.$msg->{cmd}, 
      $msg 
    );
  }

  ## issue Bot_public_msg
  $self->core->send_event( 'public_msg', $msg );
}

sub irc_msg {
  my ($self, $kernel, $src, $target, $txt) = @_[OBJECT, KERNEL, ARG0 .. ARG2];
  my $me = $self->irc->nick_name();
  $txt = strip_color( strip_formatting($txt) );
  my ($nick, $user, $host) = parse_user($src);
  ## private msg handler
  ## similar to irc_public

  my $sent_to = $target->[0];

  my $msg = {
    context => 'Main',
    myself => $me,
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    sent_to => $sent_to,  # first dest. seen
    target_array => $target,
    message => $txt,
    message_array => (split ' ', $txt),
  };

  ## Bot_private_msg
  $self->core->send_event( 'private_msg', $msg );
}

sub irc_notice {
  my ($self, $kernel, $src, $target, $txt) = @_[OBJECT, KERNEL, ARG0 .. ARG2];
  my $me = $self->irc->nick_name();
  $txt = strip_color( strip_formatting($txt) );
  my ($nick, $user, $host) = parse_user($src);

  my $msg = {
    context => 'Main',
    myself => $me,
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    sent_to => $target->[0],
    target_array => $target,
    message => $txt,
  };

  ## Bot_notice
  $self->core->send_event( 'notice', $msg );
}

sub irc_ctcp_action {
  my ($self, $kernel, $src, $target, $txt) = @_[OBJECT, KERNEL, ARG0 .. ARG2];
  my $me = $self->irc->nick_name();
  $txt = strip_color( strip_formatting($txt) );
  my ($nick, $user, $host) = parse_user($src);

  my $msg = {
    context => 'Main',  
    myself => $me,      
    src => $src,        
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    target => $target->[0],
    target_array => $target,
    message => $txt,
  };

  ## Bot_action
  $self->core->send_event( 'action', $msg );
}

sub irc_connected {
  my ($self, $kernel, $server) = @_[OBJECT, KERNEL, ARG0];

  ## IMPORTANT:
  ##  irc_connected indicates we're connected to the server
  ##  however, irc_001 is the server welcome message
  ##  irc_connected happens before auth, no guarantee we can send yet.
}

sub irc_001 {
  my ($self, $kernel) = @_[OBJECT, KERNEL, ARG0];

  $self->core->Servers->{Main}->{Connected} = 1;
  my $server = $self->irc->server_name;
  ## send a Bot_connected event with context and visible server name:
  $self->core->send_event( 'connected', 'Main', $server );
}

sub irc_disconnected {
  my ($self, $kernel, $server) = @_[OBJECT, KERNEL, ARG0];
  $self->core->Servers->{Main}->{Connected} = 0;
  ## Bot_disconnected event, similar to Bot_connected:
  $self->core->send_event( 'disconnected', 'Main', $server );
}

sub irc_error {
  my ($self, $kernel, $reason) = @_[OBJECT, KERNEL, ARG0];
  ## Bot_server_error:
  $self->core->send_event( 'server_error', 'Main', $reason );
}


sub irc_kick {
  my ($self, $kernel) = @_[OBJECT, KERNEL];
  my ($src, $channel, $target, $reason) = @_[ARG0 .. ARG3];
  my ($nick, $user, $host) = parse_user($src);

  my $kick = {
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    channel => $channel,
    target_nick => $target,
    reason => $reason,
  };

  ## Bot_user_kicked:
  $self->core->send_event( 'user_kicked', 'Main', $kick );
}

sub irc_mode {}  ## FIXME mode parser like circe?

sub irc_topic {
  my ($self, $kernel) = @_[OBJECT, KERNEL];
  my ($src, $channel, $topic) = @_[ARG0 .. ARG2];
  my ($nick, $user, $host) = parse_user($src);

  my $topic_change = {
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    channel => $channel,
    topic => $topic,
  };

  ## Bot_topic_changed
  $self->core->send_event( 'topic_changed', 'Main', $topic_change );
}

sub irc_nick {
  my ($self, $kernel, $src, $new) = @_[OBJECT, KERNEL, ARG0, ARG1];
  ## if $src is a hostmask, get just the nickname:
  my $old = parse_user($src);
  ## is this just a case change ?
  my $equal = eq_irc($old, $new) ? 1 : 0 ;
  my $nick_change = {
    old => $old,
    new => $new,
    equal => $equal,
  };

  ## Bot_nick_changed
  $self->core->send_event( 'nick_changed', 'Main', $nick_change );
}

sub irc_join {
  my ($self, $kernel, $src, $channel) = @_[OBJECT, KERNEL, ARG0, ARG1];
  my ($nick, $user, $host) = parse_user($src);

  my $join = {
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    channel  => $channel,
  };

  ## Bot_user_joined
  $self->core->send_event( 'user_joined', 'Main', $join );
}

sub irc_part {
  my ($self, $kernel) = @_[OBJECT, KERNEL];
  my ($src, $channel, $msg) = @_[ARG0 .. ARG2];

  my $part = {
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    channel => $channel,
  };

  ## Bot_user_left
  $self->core->send_event( 'user_left', 'Main', $part );
}

sub irc_quit {
  my ($self, $kernel, $src, $msg) = @_[OBJECT, KERNEL, ARG0, ARG1];
  ## depending on ircd we might get a hostmask .. or not ..
  my $nick = parse_user($src);

  my $quit = {
    src_orig => $src,
    src_nick => $nick,
    reason => $msg,
  };
}


 ### COBALT EVENTS ###

sub Bot_send_to_context {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ shift(@_) };

  return PLUGIN_EAT_NONE unless $msg->{context} eq 'Main';

  $self->irc->yield(privmsg => $msg->{target} => $msg->{txt});

  $core->send_event( 'message_sent', 'Main', $msg );

  return PLUGIN_EAT_NONE
}

sub Bot_send_to_all {
  ## catch broadcasts (MultiServer)
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ shift(@_) };

  $self->irc->yield(privmsg => $msg->{target} => $msg->{txt});

  $core->send_event( 'message_sent', 'Main', $msg );

  return PLUGIN_EAT_NONE
}

sub Bot_send_notice {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ shift(@_) };

  return PLUGIN_EAT_NONE unless $msg->{context} eq 'Main';

  $self->irc->yield(notice => $msg->{target} => $msg->{txt});
  $core->send_event( 'notice_sent', $msg );
  return PLUGIN_EAT_NONE
}

sub Bot_mode {

  ## FIXME build mode strings based on isupport MODES=
}

sub Bot_kick {
  my ($self, $core) = splice @_, 0, 2;

  ## FIXME

  return PLUGIN_EAT_NONE
}

sub Bot_join {
  my ($self, $core) = splice @_, 0, 2;
  ## FIXME

  return PLUGIN_EAT_NONE
}

sub Bot_part {

}

sub Bot_send_raw {

}



__PACKAGE__->meta->make_immutable;
no Moose; 1;

