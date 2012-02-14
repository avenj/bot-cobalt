package Cobalt::Plugin::Extras::MultiServer;
our $VERSION = '0.001';

use Cobalt::Common;

use POE;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::CTCP;
use POE::Component::IRC::Plugin::AutoJoin;
use POE::Component::IRC::Plugin::Connector;
use POE::Component::IRC::Plugin::NickServID;
use POE::Component::IRC::Plugin::NickReclaim;

## Cobalt::Common pulls the rest of these:
use IRC::Utils qw/ parse_mode_line /;

use Storable qw/dclone/;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = @_;

  $self->{core} = $core;

  $self->{IRCs} = { };

  ## register for events
  $core->plugin_register($self, 'SERVER',
    [ 'all' ],
  );

  $core->log->info("$VERSION registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  $core->log->info("Unregistering IRC plugin");

  $core->log->debug("disconnecting");

  ## shutdown IRCs
  for my $context ( keys %{ $self->{IRCs} } ) {
    $core->log->debug("shutting down irc: $context");
    ## clear auths for this context
    delete $core->State->{Auth}->{$context};
    my $irc = $self->{IRCs}->{$context};
    $irc->shutdown("IRC component shut down");
    $core->Servers->{$context}->{Connected} = 0;
  }

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
  
  my $core = $self->{core};
  my $cfg  = $core->get_plugin_cfg( $self );

  ## FIXME spawn a common ::Resolver obj ?

  SERVER: for my $context (keys %{ $cfg->{Networks} } ) {
    my $thiscfg = $cfg->{Networks}->{$context};
    
    unless (ref $thiscfg eq 'HASH' && scalar keys %$thiscfg) {
      $core->log->warn("Missing configuration: context $context");
      next SERVER
    }
    
    my $server = $thiscfg->{ServerAddr};
    my $port   = $thiscfg->{ServerPort} // 6667;
    my $nick   = $thiscfg->{Nickname} // 'cobalt2' ;
    my $usessl = $thiscfg->{UseSSL} ? 1 : 0;
    my $use_v6 = $thiscfg->{IPv6}   ? 1 : 0;
    
    $core->log->info("Spawning IRC for $context ($nick on ${server}:${port})");

    my %spawn_opts = (
      alias    => $context,
      nick     => $nick,
      username => $thiscfg->{Username} // 'cobalt',
      ircname  => $thiscfg->{Realname} // 'http://cobaltirc.org',
      server   => $server,
      port     => $port,
      useipv6  => $use_v6,
      usessl   => $usessl,
      raw => 0,
    );
  
    my $localaddr = $thiscfg->{BindAddr} || undef;
    $spawn_opts{localaddr} = $localaddr if $localaddr;
    my $server_pass = $thiscfg->{ServerPass};
    $spawn_opts{password} = $server_pass if defined $server_pass;
  
    my $i = POE::Component::IRC::State->spawn(
      %spawn_opts,
    ) or $core->log->emerg("(spawn: $context) poco-irc error: $!");

    $self->{core}->Servers->{$context} = {
      Name => $server,   ## specified server hostname
      PreferredNick => $nick,
      Object    => $i,   ## the pocoirc obj
      Connected => 0,
      # some reasonable defaults:
      CaseMap   => 'rfc1459', # for feeding eq_irc et al
      MaxModes  => 3,         # for splitting long modestrings
    };
    
    $self->{IRCs}->{$context} = $i;
  
    POE::Session->create(
      ## track this session's context name in HEAP
      heap =>  { Context => $context, Object => $i },
      object_states => [
        $self => [
          '_start',
  
          'irc_001',
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
  
    $core->log->debug("IRC Session created");
  } ## SERVER
}


 ### IRC EVENTS ###

sub _start {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];

  my $context = $heap->{Context};
  my $irc     = $heap->{Object};

  my $core = $self->{core};
  my $cfg  = $core->get_core_cfg;
  my $thiscfg = $core->get_plugin_cfg( $self );

  $core->log->debug("pocoirc plugin load");

  ## autoreconn plugin:
  my %connector;

  $connector{delay} = $cfg->{Opts}->{StonedCheck} || 300;
  $connector{reconnect} = $cfg->{Opts}->{ReconnectDelay} || 60;

  $irc->plugin_add('Connector' =>
    POE::Component::IRC::Plugin::Connector->new(
      %connector
    ),
  );

  ## attempt to regain primary nickname:
  $irc->plugin_add('NickReclaim' =>
    POE::Component::IRC::Plugin::NickReclaim->new(
        poll => $cfg->{Opts}->{NickRegainDelay} // 30,
      ), 
    );

  if (defined $thiscfg->{NickServPass}) {
    $irc->plugin_add('NickServID' =>
      POE::Component::IRC::Plugin::NickServID->new(
        Password => $thiscfg->{NickServPass},
      ),
    );
  }

  my $chanhash = $core->get_channels_cfg($context) || {};
  ## AutoJoin plugin takes a hash in form of { $channel => $passwd }:
  my %ajoin;
  for my $chan (%{ $chanhash }) {
    my $key = $chanhash->{$chan}->{password} // '';
    $ajoin{$chan} = $key;
  }

  $irc->plugin_add('AutoJoin' =>
    POE::Component::IRC::Plugin::AutoJoin->new(
      Channels => \%ajoin,
      RejoinOnKick => $cfg->{Opts}->{Chan_RetryAfterKick} // 1,
      Rejoin_delay => $cfg->{Opts}->{Chan_RejoinDelay} // 5,
      NickServ_delay    => $cfg->{Opts}->{Chan_NickServDelay} // 1,
      Retry_when_banned => $cfg->{Opts}->{Chan_RetryAfterBan} // 60,
    ),
  );

  ## define ctcp responses
  $irc->plugin_add('CTCP' =>
    POE::Component::IRC::Plugin::CTCP->new(
      version  => "cobalt ".$core->version." (perl $^V)",
      userinfo => __PACKAGE__,
      source   => 'http://www.cobaltirc.org',
    ),
  );

  ## register for all events from the component
  $irc->yield(register => 'all');
  ## initiate ze connection:
  $irc->yield(connect => {});
  $core->log->debug("irc component connect issued");
}

sub irc_chan_sync {
  my ($self, $heap, $chan) = @_[OBJECT, HEAP, ARG0];

  my $core    = $self->{core}; 
  my $irc     = $heap->{Object};
  my $context = $heap->{Context};

  my $resp = rplprintf( $core->lang->{RPL_CHAN_SYNC},
    { 'chan' => $chan }
  );

  ## issue Bot_chan_sync
  $core->send_event( 'chan_sync', $context, $chan );

  ## ON if cobalt.conf->Opts->NotifyOnSync is true or not specified:
  my $cf_core = $core->get_core_cfg();
  my $notify = 
    ($cf_core->{Opts}->{NotifyOnSync} //= 1) ? 1 : 0;

  my $chan_h = $core->get_channels_cfg( $context ) || {};

  ## check if we have a specific setting for this channel (override):
  if ( exists $chan_h->{$chan}
       && ref $chan_h->{$chan} eq 'HASH' 
       && exists $chan_h->{$chan}->{notify_on_sync} ) 
  {
    $notify = $chan_h->{$chan}->{notify_on_sync} ? 1 : 0;
  }

  $irc->yield(privmsg => $chan => $resp) if $notify;
}

sub irc_public {
  my ($self, $heap, $kernel) = @_[OBJECT, HEAP, KERNEL];
  my ($src, $where, $txt) = @_[ ARG0 .. ARG2 ];
  
  my $core    = $self->{core};
  my $irc     = $heap->{Object};
  my $context = $heap->{Context};
  
  my $me = $irc->nick_name();
  my $orig = $txt;
  $txt = strip_color( strip_formatting($txt) );
  my ($nick, $user, $host) = parse_user($src);
  my $channel = $where->[0];

  my $casemap = $core->get_irc_casemap( $context );
  ## FIXME: per-context Ignores
  for my $mask (keys %{ $core->State->{Ignored} }) {
    ## Check against ignore list
    ## (Ignore list should be keyed by hostmask)
    return if matches_mask( $mask, $src, $casemap );
  }

  my $msg = {
    context => $context,
    myself => $me, 
    src    => $src, 
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    channel  => $channel,
    target   => $channel, # maintain compat with privmsg handler
    target_array => $where, # array
    highlight => 0,
    cmdprefix => 0,
    message => $txt,  # stripped text
    orig => $orig,    # the original unparsed text
    message_array => [ split ' ', $txt ],
  };

  $msg->{highlight} = 1 if $txt =~ /^${me}.?\s+/i;
  $msg->{highlighted} = $msg->{highlight};

  my $cf_core = $core->get_core_cfg();
  my $cmdchar = $cf_core->{Opts}->{CmdChar} // '!';
  if ( $txt =~ /^${cmdchar}([^\s]+)/ ) {
    ## Commands always get lowercased:
    my $cmd = lc $1;
    $msg->{cmd} = $cmd;
    $msg->{cmdprefix} = 1;

    ## IMPORTANT:
    ## this is a _public_cmd_, so we shift message_array leftwards.
    ## this means the command *without prefix* is in $msg->{cmd}
    ## the text array *without command or prefix* is in $msg->{message_array}
    ## the original unmodified string is in $msg->{orig}
    ## the format/color-stripped string is in $msg->{message}
    ## the text array here may well be empty (no args specified)

    my $cmd_msg = dclone($msg);
    shift @{ $cmd_msg->{message_array} };

    ## issue a public_cmd_$cmd event to plugins (w/ different ref)
    ## command-only plugins can choose to only receive specified events
    $core->send_event( 
      'public_cmd_'.$cmd,
      $context, 
      $cmd_msg
    );
  }

  ## issue Bot_public_msg (plugins will get _cmd_ events first!)
  $core->send_event( 'public_msg', $context, $msg );
}

sub irc_msg {
  my ($self, $heap, $kernel) = @_[OBJECT, HEAP, KERNEL];
  my ($src, $target, $txt) = @_[ARG0 .. ARG2];

  my $core    = $self->{core};
  my $context = $heap->{Context};
  my $irc     = $heap->{Object};

  my $me = $irc->nick_name();
  my $orig = $txt;
  $txt = strip_color( strip_formatting($txt) );
  my ($nick, $user, $host) = parse_user($src);

  ## private msg handler
  ## similar to irc_public

  my $casemap = $core->get_irc_casemap( $context );
  for my $mask (keys %{ $self->{core}->State->{Ignored} }) {
    ## FIXME per-context ignorelist
    return if matches_mask( $mask, $src, $casemap );
  }

  my $sent_to = $target->[0];

  my $msg = {
    context => $context,
    myself  => $me,
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    target   => $sent_to,
    target_array => $target,
    message => $txt,
    orig    => $orig,
    message_array => [ split ' ', $txt ],
  };

  ## Bot_private_msg
  $core->send_event( 'private_msg', $context, $msg );
}

sub irc_notice {
  my ($self, $heap, $kernel) = @_[OBJECT, HEAP, KERNEL];
  my ($src, $target, $txt) = @_[ARG0 .. ARG2];

  my $core    = $self->{core};
  my $context = $heap->{Context};
  my $irc     = $heap->{Object};

  my $me = $irc->nick_name();
  my $orig = $txt;
  $txt = strip_color( strip_formatting($txt) );
  my ($nick, $user, $host) = parse_user($src);

  my $casemap = $core->get_irc_casemap($context) // 'rfc1459';
  for my $mask (keys %{ $self->{core}->State->{Ignored} }) {
    return if matches_mask( $mask, $src, $casemap );
  }

  my $msg = {
    context => $context,
    myself  => $me,
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    target => $target->[0],
    target_array => $target,
    message => $txt,
    orig    => $orig,
    message_array => [ split ' ', $txt ],
  };

  ## Bot_notice
  $self->{core}->send_event( 'notice', $context, $msg );
}

sub irc_ctcp_action {
  my ($self, $heap, $kernel) = @_[OBJECT, HEAP, KERNEL];
  my ($src, $target, $txt) = @_[ARG0 .. ARG2];

  my $core    = $self->{core};
  my $context = $heap->{Context};
  my $irc     = $heap->{Object};

  my $me = $irc->nick_name();
  my $orig = $txt;
  $txt = strip_color( strip_formatting($txt) );
  my ($nick, $user, $host) = parse_user($src);

  for my $mask (keys %{ $self->{core}->State->{Ignored} }) {
    return if matches_mask( $mask, $src );
  }

  my $msg = {
    context => $context, 
    myself  => $me,      
    src => $src,        
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    target   => $target->[0],
    target_array => $target,
    message => $txt,
    orig    => $orig,
    message_array => [ split ' ', $txt ],
  };

  ## if this is a public ACTION, add a 'channel' key
  ## same as ->target, but convenient for differentiating
  $msg->{channel} = $target->[0] 
    if $target->[0] ~~ [ split '', '#&+' ];

  ## Bot_ctcp_action
  $core->send_event( 'ctcp_action', $context, $msg );
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
  my ($self, $heap, $kernel) = @_[OBJECT, HEAP, KERNEL];

  my $core    = $self->{core};
  my $context = $heap->{Context};
  my $irc     = $heap->{Object};

  ## server welcome message received.
  ## set up some stuff relevant to our server context:
  $core->Servers->{$context}->{Connected} = 1;
  $core->Servers->{$context}->{ConnectedAt} = time;
  $core->Servers->{$context}->{MaxModes} = 
    $irc->isupport('MODES') // 4;
  ## irc comes with odd case-mapping rules.
  ## []\~ are considered uppercase equivalents of {}|^
  ##
  ## this may vary by server
  ## (most servers are rfc1459, some are -strict, some are ascii)
  ##
  ## we can tell eq_irc/uc_irc/lc_irc to do the right thing by 
  ## checking ISUPPORT and setting the casemapping if available
  my $casemap = lc( $irc->isupport('CASEMAPPING') || 'rfc1459' );
  $core->Servers->{$context}->{CaseMap} = $casemap;
  
  ## if the server returns a fubar value (hi, paradoxirc) IRC::Utils
  ## automagically defaults to rfc1459 casemapping rules
  ## 
  ## this is unavoidable in some situations, however:
  ## misconfigured inspircd on paradoxirc gives a codepage for CASEMAPPING
  ## and a casemapping for CHARSET (which is supposed to be deprecated)
  ## I strongly suspect there are other similarly broken servers around.
  ##
  ## we can try to check for this, but it's still a crapshoot.
  ##
  ## this 'fix' will still break when CASEMAPPING is nonsense and CHARSET
  ## is set to 'ascii' but other casemapping rules are being followed.
  ##
  ## the better fix is to smack your admins with a hammer.
  my @valid_casemaps = qw/ rfc1459 ascii strict-rfc1459 /;
  unless ($casemap ~~ @valid_casemaps) {
    my $charset = lc( $irc->isupport('CHARSET') || '' );
    if ($charset && $charset ~~ @valid_casemaps) {
      $core->Servers->{$context}->{CaseMap} = $charset;
    }
    ## we don't save CHARSET, it's deprecated per the spec
    ## also mostly unreliable and meaningless
    ## you're on your own for handling fubar encodings.
    ## http://www.irc.org/tech_docs/draft-brocklesby-irc-isupport-03.txt
  }

  my $server = $irc->server_name;
  $core->log->info("Connected: $context: $server");
  ## send a Bot_connected event with context and visible server name:
  $self->{core}->send_event( 'connected', $context, $server );
}

sub irc_disconnected {
  my ($self, $kernel, $server) = @_[OBJECT, KERNEL, ARG0];
  my $context = $_[HEAP]->{Context};
  $self->{core}->log->info("IRC disconnected: $context");
  $self->{core}->Servers->{$context}->{Connected} = 0;
  ## Bot_disconnected event, similar to Bot_connected:
  $self->{core}->send_event( 'disconnected', $context, $server );
}

sub irc_error {
  my ($self, $kernel, $reason) = @_[OBJECT, KERNEL, ARG0];
  ## Bot_server_error:
  my $context = $_[HEAP]->{Context};
  $self->{core}->log->warn("IRC error: $context: $reason");
  $self->{core}->send_event( 'server_error', $context, $reason );
}


sub irc_kick {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my ($src, $channel, $target, $reason) = @_[ARG0 .. ARG3];
  my ($nick, $user, $host) = parse_user($src);

  my $context = $heap->{Context};
  my $irc     = $heap->{Object};
  my $core    = $self->{core};

  my $kick = {
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    channel => $channel,
    kicked => $target,
    target => $target,  # kicked/target are both valid
    reason => $reason,
  };

  my $me = $irc->nick_name();
  my $casemap = $core->get_irc_casemap($context);
  if ( eq_irc($me, $nick, $casemap) ) {
    ## Bot_self_kicked:
    $core->send_event( 'self_kicked', $context, $src, $channel, $reason );
  }

  ## Bot_user_kicked:
  $core->send_event( 'user_kicked', $context, $kick );
}

sub irc_mode {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my ($src, $changed_on, $modestr, @modeargs) = @_[ ARG0 .. $#_ ];
  
  my $irc     = $heap->{Object};
  my $context = $heap->{Context};
  my $core    = $self->{core};
  
  my ($nick, $user, $host) = parse_user($src);

  ## shouldfix; split into modes with args and modes without based on isupport?

  my $modechg = {
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    channel => $changed_on,
    mode => $modestr,
    args => [ @modeargs ],
    ## shouldfix; try to parse isupport to feed parse_mode_line chan/status lines?
    ## (code to sort-of do this in embedded POD)
    hash => parse_mode_line($modestr, @modeargs),
  };
  ## try to guess whether the mode change was umode (us):
  my $me = $irc->nick_name();
  my $casemap = $core->get_irc_casemap($context);
  if ( eq_irc($me, $changed_on, $casemap) ) {
    ## our umode changed
    $core->send_event( 'umode_changed', $context, $modestr );
    return
  }

  ## otherwise it's mostly safe to assume mode changed on a channel
  ## could check by grabbing isupport('CHANTYPES') and checking against
  ## is_valid_chan_name from IRC::Utils, f.ex:
  ## my $chantypes = $self->irc->isupport('CHANTYPES') || '#&';
  ## is_valid_chan_name($changed_on, [ split '', $chantypes ]) ? 1 : 0;
  ## ...but afaik this Should Be Fine:
  $core->send_event( 'mode_changed', $context, $modechg);
}

sub irc_topic {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my ($src, $channel, $topic) = @_[ARG0 .. ARG2];
  my ($nick, $user, $host) = parse_user($src);

  my $context = $heap->{Context};
  my $irc     = $heap->{Object};
  my $core    = $self->{core};

  my $topic_change = {
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    channel => $channel,
    topic => $topic,
  };

  ## Bot_topic_changed
  $core->send_event( 'topic_changed', $context, $topic_change );
}

sub irc_nick {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my ($src, $new) = @_[ARG0, ARG1];

  my $context = $heap->{Context};
  my $irc     = $heap->{Object};
  my $core    = $self->{core};

  ## if $src is a hostmask, get just the nickname:
  my $old = parse_user($src);

  ## see if it's our nick that changed, send event:
  if ($new eq $irc->nick_name) {
    $self->{core}->send_event( 'self_nick_changed', $context, $new );
  }

  my $casemap = $core->get_irc_casemap($context);
  ## is this just a case change ?
  my $equal = eq_irc($old, $new, $casemap) ? 1 : 0 ;
  my $nick_change = {
    old => $old,
    new => $new,
    equal => $equal,
  };

  ## Bot_nick_changed
  $core->send_event( 'nick_changed', $context, $nick_change );
}

sub irc_join {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my ($src, $channel) = @_[ARG0, ARG1];

  my $context = $heap->{Context};
  my $irc     = $heap->{Object};
  my $core    = $self->{core};

  my ($nick, $user, $host) = parse_user($src);

  my $join = {
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    channel  => $channel,
  };

  ## Bot_user_joined
  $core->send_event( 'user_joined', $context, $join );
}

sub irc_part {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my ($src, $channel, $msg) = @_[ARG0 .. ARG2];

  my $context = $heap->{Context};
  my $irc     = $heap->{Object};
  my $core    = $self->{core};
  
  my ($nick, $user, $host) = parse_user($src);

  my $part = {
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    channel => $channel,
  };

  my $me = $irc->nick_name();
  my $casemap = $core->get_irc_casemap($context);
  ## shouldfix? we could try an 'eq' here ... but is a part issued by
  ## force methods going to be guaranteed the same case ... ?
  if ( eq_irc($me, $nick, $casemap) ) {
    ## we were the issuer of the part -- possibly via /remove, perhaps?
    ## (autojoin might bring back us back, though)
    $core->send_event( 'self_left', $context, $channel );
  }

  ## Bot_user_left
  $core->send_event( 'user_left', $context, $part );
}

sub irc_quit {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my ($src, $msg) = @_[ARG0, ARG1];
  ## depending on ircd we might get a hostmask .. or not ..
  my ($nick, $user, $host) = parse_user($src);

  my $context = $heap->{Context};
  my $irc     = $heap->{Object};
  my $core    = $self->{core};

  my $quit = {
    src => $src,
    src_nick => $nick,
    src_user => $user,
    src_host => $host,
    reason => $msg,
  };

  ## Bot_user_quit
  $core->send_event( 'user_quit', $context, $quit );
}


 ### COBALT EVENTS ###

sub Bot_send_message {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $target  = ${$_[1]};
  my $txt     = ${$_[2]};

  ## core->send_event( 'send_message', $context, $target, $string );

  unless ( $context
           && $self->{IRCs}->{$context}
           && $target
           && $txt
  ) { 
    return PLUGIN_EAT_NONE 
  }
  
  return PLUGIN_EAT_NONE unless $core->Servers->{$context}->{Connected};

  ## Issue USER event Outgoing_message for output filters
  my @msg = ( $context, $target, $txt );
  my $eat = $core->send_user_event( 'message', \@msg );
  unless ($eat == PLUGIN_EAT_ALL) {
    my ($target, $txt) = @msg[1,2];
    $self->{IRCs}->{$context}->yield(privmsg => $target => $txt);
    $core->send_event( 'message_sent', $context, $target, $txt );
    ++$core->State->{Counters}->{Sent};
  }

  return PLUGIN_EAT_NONE
}

sub Bot_send_notice {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $target  = ${$_[1]};
  my $txt     = ${$_[2]};

  ## core->send_event( 'send_notice', $context, $target, $string );

  unless ( $context
           && $self->{IRCs}->{$context}
           && $target
           && $txt
  ) { 
    return PLUGIN_EAT_NONE 
  }

  return PLUGIN_EAT_NONE unless $core->Servers->{$context}->{Connected};

  ## USER event Outgoing_notice
  my @notice = ( $context, $target, $txt );
  my $eat = $core->send_user_event( 'notice', \@notice );
  unless ($eat == PLUGIN_EAT_ALL) {
    my ($target, $txt) = @notice[1,2];
    $self->{IRCs}->{$context}->yield(notice => $target => $txt);
    $core->send_event( 'notice_sent', $context, $target, $txt );
  }

  return PLUGIN_EAT_NONE
}

sub Bot_send_action {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $target  = ${$_[1]};
  my $txt     = ${$_[2]};

  ## core->send_event( 'send_action', $context, $target, $string );

  unless ( $context
           && $self->{IRCs}->{$context}
           && $target
           && $txt
  ) { 
    return PLUGIN_EAT_NONE 
  }

  return PLUGIN_EAT_NONE unless $core->Servers->{$context}->{Connected};
  
  ## USER event Outgoing_ctcp (CONTEXT, TYPE, TARGET, TEXT)
  my @ctcp = ( $context, 'ACTION', $target, $txt );
  my $eat = $core->send_user_event( 'ctcp', \@ctcp );
  unless ($eat == PLUGIN_EAT_ALL) {
    my ($target, $txt) = @ctcp[2,3];
    $self->{IRCs}->{$context}->yield(ctcp => $target => 'ACTION '.$txt );
    $core->send_event( 'ctcp_sent', $context, 'ACTION', $target, $txt );
  }

  return PLUGIN_EAT_NONE
}

sub Bot_topic {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $channel = ${$_[1]};
  my $topic   = ${$_[2] || \''};

  unless ( $context
           && $self->{IRCs}->{$context}
           && $channel
  ) { 
    return PLUGIN_EAT_NONE 
  }

  return PLUGIN_EAT_NONE unless $core->Servers->{$context}->{Connected};

  $self->irc->yield( 'topic', $channel, $topic );

  return PLUGIN_EAT_NONE
}

sub Bot_mode {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $target  = ${$_[1]}; ## channel or self normally
  my $modestr = ${$_[2]}; ## modes + args

  unless ( $context
           && $self->{IRCs}->{$context}
           && $target
           && $modestr
  ) { 
    return PLUGIN_EAT_NONE 
  }

  return PLUGIN_EAT_NONE unless $core->Servers->{$context}->{Connected};

  my ($mode, @args) = split ' ', $modestr;

  $self->{IRCs}->{$context}->yield( 'mode', $target, $mode, @args );

  return PLUGIN_EAT_NONE
}

sub Bot_kick {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $channel = ${$_[1]};
  my $target  = ${$_[2]};
  my $reason  = ${$_[3] // \'Kicked'};

  unless ( $context
           && $self->{IRCs}->{$context}
           && $channel
           && $target
  ) { 
    return PLUGIN_EAT_NONE 
  }      

  return PLUGIN_EAT_NONE unless $core->Servers->{$context}->{Connected};

  $self->{IRCs}->{$context}->yield( 'kick', $channel, $target, $reason );

  return PLUGIN_EAT_NONE
}

sub Bot_join {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $channel = ${$_[1]};

  unless ( $context
           && $self->{IRCs}->{$context}
           && $channel
  ) { 
    return PLUGIN_EAT_NONE 
  }

  return PLUGIN_EAT_NONE unless $core->Servers->{$context}->{Connected};

  $self->{IRCs}->{$context}->yield( 'join', $channel );

  return PLUGIN_EAT_NONE
}

sub Bot_part {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $channel = ${$_[1]};
  my $reason  = ${$_[2] // \'Leaving' };

  unless ( $context
           && $self->{IRCs}->{$context}
           && $channel
  ) { 
    return PLUGIN_EAT_NONE 
  }      

  return PLUGIN_EAT_NONE unless $core->Servers->{$context}->{Connected};

  $self->{IRCs}->{$context}->yield( 'part', $channel, $reason );

  return PLUGIN_EAT_NONE
}

sub Bot_send_raw {
  my ($self, $core) = splice @_, 0, 2;
  ## FIXME

  return PLUGIN_EAT_NONE

}

1;
__END__
