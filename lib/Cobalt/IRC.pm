package Cobalt::IRC;

## Core IRC plugin
## (server context 'Main')

use 5.14.1;
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

  $self->core->log->info("Spawning IRC, server: ($nick) $server $port");

  my $i = POE::Component::IRC::State->spawn(
    nick     => $nick,
    username => $cfg->{IRC}->{Username} || 'cobalt',
    ircname  => $cfg->{IRC}->{Realname}  || 'http://cobaltirc.org',
    server   => $server,
    port     => $port,
    raw => 0,
  ) or $self->core->log->emerg("poco-irc error: $!");

  ## add 'Main' to connected servers
  $self->core->Servers->{Main} = {
    Name => $server,
    PreferredNick => $nick,
    Object => $i,
    ConnectedAt => time(),
  };

  $self->irc($i);

  POE::Session->create(
    object_states => [
      $self => [
        '_start',
        'irc_chan_sync',
        'irc_public',
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
    POE::Component::IRC::Plugin::NickReclaim->new( poll => 30 ) );
# FIXME conf:
#  $self->irc->plugin_add('NickServID' =>
#    POE::Component::IRC::Plugin::NickServID->new (
#      Password => $cfg->{opts}->{nickserv_passwd} // '',
#    ),
#  );

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
  $self->irc->yield(connect => { });
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
  my $channel = $where->[0];
  my $me = $self->irc->nick_name();
  $txt = strip_color( strip_formatting($txt) );
  my ($nick, $user, $host) = parse_user($src);

  ## FIXME create a msg packet like circe and send_event to self->core

  my $msg = {
    context => 'Main',  # server context
    myself => $me,      # bot's current nickname
    src => $src,        # full Nick!User@Host
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    highlight => 0,
    message => $txt,
  };

  ## flag messages seemingly directed at the bot
  ## makes life easier for plugins
  $msg->{highlight} = 1 if $txt =~ /^${me}.?\s+/i;

  ## issue Bot_public_msg
  $self->core->send_event( 'public_msg', $msg );
}

## FIXME moar irc events


 ### COBALT EVENTS ###

sub Bot_send_to_context {
  ## FIXME dispatch messages based on context

  return PLUGIN_EAT_NONE;
}



__PACKAGE__->meta->make_immutable;
no Moose; 1;
