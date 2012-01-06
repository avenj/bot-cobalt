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

 Bot_message_sent
 Bot_notice_sent

 Bot_chan_sync

 Bot_public_msg
 Bot_private_msg
 Bot_notice

 Bot_topic_changed
 Bot_mode_changed
 Bot_nick_changed

 Bot_user_joined
 Bot_user_left
 Bot_user_quit
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

use IRC::Utils qw/
  parse_user
  lc_irc uc_irc eq_irc
  strip_color strip_formatting
  matches_mask normalize_mask
/;

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

  ## give ourselves an Auth hash
  $core->State->{Auth}->{Main} = { };

  $core->log->info(__PACKAGE__." registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  $core->log->info("Unregistering core IRC plugin");
  $core->log->debug("clearing 'Main' context from Auth");
  delete $core->State->{Auth}->{Main};
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
    usessl   => $usessl,
    raw => 0,
  ) or $self->core->log->emerg("poco-irc error: $!");

  ## add 'Main' to Servers:
  $self->core->Servers->{Main} = {
    Name => $server,   ## specified server hostname
    PreferredNick => $nick,
    Object => $i,      ## the pocoirc obj

    ## flipped by irc_001 events:
    Connected => 0,
    # some reasonable defaults:
    CaseMap => 'rfc1459', # for feeding eq_irc et al
    MaxModes => 3,        # for splitting long modestrings
    
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

  ## autoreconn plugin:

  ## FIXME: Connector can be provided a list of servers
  ## docs say it should be in the format of:
  ## [ [$host, $port], [$host, $port], ... ]

  $self->irc->plugin_add('Connector' =>
    POE::Component::IRC::Plugin::Connector->new);

  ## attempt to regain primary nickname:
  $self->irc->plugin_add('NickReclaim' =>
    POE::Component::IRC::Plugin::NickReclaim->new(
        poll => $cfg->{Opts}->{NickRegainDelay} // 30,
      ), 
    );

  ## see if we should be identifying to nickserv automagically
  ## note that the 'Main' context's nickservpass exists in cobalt.conf:
  if ($cfg->{IRC}->{NickServPass}) {
    $self->irc->plugin_add('NickServID' =>
      POE::Component::IRC::Plugin::NickServID->new(
        Password => $cfg->{IRC}->{NickServPass},
      ),
    );
  }

  ## channel config to feed autojoin plugin
  ## single-server core irc module just grabs 'Main' context
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

  ## define ctcp responses
  $self->irc->plugin_add('CTCP' =>
    POE::Component::IRC::Plugin::CTCP->new(
      version => "cobalt ".$self->core->version." (perl $^V)",
      userinfo => __PACKAGE__,
    ),
  );

  ## register for all events from the component
  $self->irc->yield(register => 'all');

  my $opts = { };

  ## see if we should be specifying a local bindaddr:
  my $localaddr = $cfg->{IRC}->{BindAddr} // 0;
  $opts->{localaddr} = $localaddr if $localaddr;
  ## .. or passwd:
  my $server_pass = $cfg->{IRC}->{ServerPass} // 0;
  $opts->{password} = $server_pass if $server_pass;
  ## (could just as easily set these up at spawn, granted)

  ## initiate ze connection:
  $self->irc->yield(connect => $opts);
  $self->core->log->debug("irc component connect issued");
}

sub irc_chan_sync {
  my ($self, $chan) = @_[OBJECT, ARG0];

  my $resp = sprintf( $self->core->lang->{RPL_CHAN_SYNC}, $chan );

  ## issue Bot_chan_sync
  $self->core->send_event( 'chan_sync', $chan );

  ## ON if cobalt.conf->Opts->NotifyOnSync is true or not specified:
  my $notify = 
    ($self->core->cfg->{core}->{Opts}->{NotifyOnSync} //= 1) ? 1 : 0;

  ## check if we have a specific setting for this channel (override):
  my $chan_h = $self->core->cfg->{channels}->{Main} // { };
  if ( exists $chan_h->{$chan}
       && ref $chan_h->{$chan} eq 'HASH' 
       && exists $chan_h->{$chan}->{notify_on_sync} ) 
  {
    $notify = $chan_h->{$chan}->{notify_on_sync} ? 1 : 0;
  }

  $self->irc->yield(privmsg => $chan => $resp)
    if $notify;
}

sub irc_public {
  my ($self, $kernel) = @_[OBJECT, KERNEL];
  my ($src, $where, $txt) = @_[ ARG0 .. ARG2 ];
  my $me = $self->irc->nick_name();
  my $orig = $txt;
  $txt = strip_color( strip_formatting($txt) );
  my ($nick, $user, $host) = parse_user($src);
  my $channel = $where->[0];

  my $map = $self->core->Servers->{Main}->{CaseMap} // 'rfc1459';
  for my $mask (keys $self->core->State->{Ignored}) {
    ## Check against ignore list
    ## (Ignore list should be keyed by hostmask)
    return if matches_mask( $mask, $src, $map );
  }

  ## create a msg hash and send_event to self->core
  ## we do a bunch of work here so plugins don't have to:

  ## IMPORTANT:
  ## note that we don't decode_irc() here.
  ##
  ## this means that text consists of byte strings of unknown encoding!
  ## storing or displaying the text may present complications.
  ## 
  ## ( see http://search.cpan.org/perldoc?IRC::Utils#ENCODING )
  ## before writing or displaying text it may be wise for plugins to
  ## run the string though decode_irc()
  ##
  ## when replying, always reply to the original byte-string.
  ## channel names may be an unknown encoding also.

  my $msg = {
    context => 'Main',  # server context
    myself => $me,      # bot's current nickname
    src => $src,        # full Nick!User@Host
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    channel => $channel,  # first dest. channel seen
    target_array => $where, # array of all chans seen
    highlight => 0,  # these two are set up below
    cmdprefix => 0,
    message => $txt,  # the color/format-stripped text
    # also included in array format:
    message_array => [ split ' ', $txt ],
    orig => $orig,    # the original unparsed text
  };

  ## flag messages seemingly directed at the bot
  ## makes life easier for plugins
  $msg->{highlight} = 1 if $txt =~ /^${me}.?\s+/i;

  ## flag messages prefixed by cmdchar
  my $cmdchar = $self->core->cfg->{core}->{Opts}->{CmdChar} // '!';
  if ( $txt =~ /^${cmdchar}([^\s]+)/ ) {
    $msg->{cmdprefix} = 1;
    ## Commands always get lowercased:
    $msg->{cmd} = lc $1;

    ## IMPORTANT:
    ## this is a _public_cmd_, so we shift message_array leftwards.
    ## this means the command *without prefix* is in $msg->{cmd}
    ## the text array *without command or prefix* is in $msg->{message_array}
    ## the original unmodified string is in $msg->{orig}
    ## the format/color-stripped string is in $msg->{txt}
    ## the text array here may well be empty (no args specified)
    shift @{ $msg->{message_array} };

    ## issue a public_cmd_$cmd event to plugins
    ## command-only plugins can choose to only receive specified events
    $self->core->send_event( 
      'public_cmd_'.$msg->{cmd},
      'Main', 
      $msg 
    );
  }

  ## issue Bot_public_msg (plugins will get _cmd_ events first!)
  $self->core->send_event( 'public_msg', 'Main', $msg );
}

sub irc_msg {
  my ($self, $kernel, $src, $target, $txt) = @_[OBJECT, KERNEL, ARG0 .. ARG2];
  my $me = $self->irc->nick_name();
  my $orig = $txt;
  $txt = strip_color( strip_formatting($txt) );
  my ($nick, $user, $host) = parse_user($src);

  ## private msg handler
  ## similar to irc_public

  my $map = $self->core->Servers->{Main}->{CaseMap} // 'rfc1459';
  for my $mask (keys $self->core->State->{Ignored}) {
    return if matches_mask( $mask, $src, $map );
  }

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
    orig => $orig,
    message_array => [ split ' ', $txt ],
  };

  ## Bot_private_msg
  $self->core->send_event( 'private_msg', 'Main', $msg );
}

sub irc_notice {
  my ($self, $kernel, $src, $target, $txt) = @_[OBJECT, KERNEL, ARG0 .. ARG2];
  my $me = $self->irc->nick_name();
  $txt = strip_color( strip_formatting($txt) );
  my ($nick, $user, $host) = parse_user($src);

  my $map = $self->core->Servers->{Main}->{CaseMap} // 'rfc1459';
  for my $mask (keys $self->core->State->{Ignored}) {
    return if matches_mask( $mask, $src, $map );
  }

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
    message_array => [ split ' ', $txt ],
  };

  ## Bot_notice
  $self->core->send_event( 'notice', 'Main', $msg );
}

sub irc_ctcp_action {
  my ($self, $kernel, $src, $target, $txt) = @_[OBJECT, KERNEL, ARG0 .. ARG2];
  my $me = $self->irc->nick_name();
  $txt = strip_color( strip_formatting($txt) );
  my ($nick, $user, $host) = parse_user($src);

  for my $mask (keys $self->core->State->{Ignored}) {
    return if matches_mask( $mask, $src );
  }

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
  $self->core->send_event( 'action', 'Main', $msg );
}

sub irc_connected {
  my ($self, $kernel, $server) = @_[OBJECT, KERNEL, ARG0];

  ## NOTE:
  ##  irc_connected indicates we're connected to the server
  ##  however, irc_001 is the server welcome message
  ##  irc_connected happens before auth, no guarantee we can send yet.
  ##  (we don't broadcast Bot_connected until irc_001)
}

sub irc_001 {
  my ($self, $kernel) = @_[OBJECT, KERNEL, ARG0];

  ## server welcome message received.
  ## set up some stuff relevant to our server context:
  $self->core->Servers->{Main}->{Connected} = 1;
  $self->core->Servers->{Main}->{MaxModes} = 
    $self->irc->isupport('MODES') // 4;
  ## irc comes with odd case-mapping rules.
  ## we can tell eq_irc/uc_irc/lc_irc to do the right thing by 
  ## checking ISUPPORT and setting the casemapping if available
  ## (most servers are rfc1459, some are -strict, some are ascii)
  $self->core->Servers->{Main}->{CaseMap} =
    $self->irc->isupport('CASEMAPPING') // 'rfc1459';

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
  ## not a socket error, but the IRC server hates you.
  ## maybe you got zlined. :)
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

sub irc_mode {
  my ($self, $kernel) = @_[OBJECT, KERNEL];

  my ($src, $changed_on, $modestr, @modeargs) = @_[ ARG0 .. $#_ ];

  my $modechg; ## FIXME
  
  $self->core->send_event( 'mode_changed', 'Main', $modechg);
}

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
  my $map = $self->core->Servers->{Main}->{CaseMap} // 'rfc1459';
  my $equal = eq_irc($old, $new, $map) ? 1 : 0 ;
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
  my ($nick, $user, $host) = parse_user($src);
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

  ## Bot_user_quit
  $self->core->send_event( 'user_quit', 'Main', $quit );
}


 ### COBALT EVENTS ###

sub Bot_send_to_context {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ $_[0] };

  ## core->send_event( 'send_to_context', $msgHash );
  ## msgHash = {
  ##   target => $nick or $chan,
  ##   context => $server_context,
  ##   txt => $string,
  ## }

  return PLUGIN_EAT_NONE unless $msg->{context} eq 'Main';

  $self->irc->yield(privmsg => $msg->{target} => $msg->{txt});

  $core->send_event( 'message_sent', 'Main', $msg );
  ++$core->State->{Counters}->{Sent};

  return PLUGIN_EAT_NONE
}

sub Bot_send_notice {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ $_[0] };  ## FIXME better interfaces?

  return PLUGIN_EAT_NONE unless $msg->{context} eq 'Main';

  $self->irc->yield(notice => $msg->{target} => $msg->{txt});

  $core->send_event( 'notice_sent', $msg );

  return PLUGIN_EAT_NONE
}

sub Bot_mode {
  my ($self, $core) = splice @_, 0, 2;
  ## FIXME
  return PLUGIN_EAT_NONE
}

sub Bot_kick {
  my ($self, $core) = splice @_, 0, 2;
  ## send_event( 'kick', $channel, $nick, $context)
  ## assume 'Main' context if none specified.
  ## shouldfix to 'best guess' based on current channels...

  ## FIXME


  return PLUGIN_EAT_NONE
}

sub Bot_join {
  my ($self, $core) = splice @_, 0, 2;
  my $chan = ${ $_[0] };

  ## FIXME


  return PLUGIN_EAT_NONE
}

sub Bot_part {
  my ($self, $core) = splice @_, 0, 2;
  ## FIXME

  return PLUGIN_EAT_NONE

}

sub Bot_send_raw {
  my ($self, $core) = splice @_, 0, 2;
  ## FIXME

  return PLUGIN_EAT_NONE

}



__PACKAGE__->meta->make_immutable;
no Moose; 1;

