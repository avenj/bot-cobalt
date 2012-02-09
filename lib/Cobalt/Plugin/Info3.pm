package Cobalt::Plugin::Info3;
our $VERSION = '0.17';

## Handles glob-style "info" response topics
## Modelled on darkbot/cobalt1 behavior
## Commands:
##  <bot> add
##  <bot> del(ete)
##  <bot> replace
##  <bot> (d)search
##
## Also handles darkbot-style variable replacement

use 5.12.1;
use strict;
use warnings;
use Carp;

use DateTime;

use Object::Pluggable::Constants qw/ :ALL /;

use Cobalt::Utils qw/ :ALL /;

use Cobalt::DB;

## borrow RDB's SearchCache
use Cobalt::Plugin::RDB::SearchCache;

sub new { bless( {}, shift ) }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;

  $self->{Cache} = Cobalt::Plugin::RDB::SearchCache->new(
    MaxKeys => 20,
  );

  my $cfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $var = $core->var;
  my $relative_to_var = $cfg->{Opts}->{InfoDB} // 'db/info3.db';
  my $dbpath = $var ."/". $relative_to_var;
  $self->{DB_PATH} = $dbpath;
  $self->{DB} = Cobalt::DB->new(
    File => $dbpath,
  );

  ## glob-to-re mapping:
  $self->{Globs} = { };
  ## reverse of above:
  $self->{Regexes} = { };
  
  ## build our initial hashes:
  $self->{DB}->dbopen || croak 'DB open failure';
  for my $glob ($self->{DB}->dbkeys) {
    ++$core->Provided->{info_topics};
    my $ref = $self->{DB}->get($glob);
    my $regex = $ref->{Regex};
    $self->{Globs}->{$glob} = $regex;
    $self->{Regexes}->{$regex} = $glob;
  }
  $self->{DB}->dbclose;

  $core->plugin_register($self, 'SERVER',
    [ 
      'public_msg',
      'ctcp_action',
      'info3_relay_string',
    ],
  );

  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  delete $core->Provided->{info_topics};
  $core->log->info("Unregistering Info plugin");
  return PLUGIN_EAT_NONE
}

sub Bot_ctcp_action {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};
  ## similar to _public_msg handler
  ## pre-pend ~action+ and run a match

  my @message = @{ $msg->{message_array} };
  return PLUGIN_EAT_NONE unless @message;

  my $str = join ' ', '~action', @message;
  my $match = $self->_info_match($str) || return PLUGIN_EAT_NONE;

  my $nick = $msg->{src_nick};
  my $channel = $msg->{target};

  ## is this a channel? ctcp_action doesn't differentiate on its own
  return PLUGIN_EAT_NONE 
    unless substr($channel, 0, 1) ~~ [ '#', '&', '+' ] ;

  if ( index($match, '~') == 0) {
    my $rdb = (split ' ', $match)[0];
    $rdb = substr($rdb, 1);
    if ($rdb) {
      $core->send_event( 'rdb_triggered',
        $context,
        $channel,
        $nick,
        lc($rdb),
        $match
      );
      return PLUGIN_EAT_NONE
    }
  }

  $core->log->debug("issuing info3_relay_string in response to action");
  $core->send_event( 'info3_relay_string', 
    $context, $channel, $nick, $match
  );
  return PLUGIN_EAT_NONE
}

sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};
  
  ## if this is a !cmd, discard it:
  return PLUGIN_EAT_NONE if $msg->{cmdprefix};
  
  ## also discard if we have no useful text:
  my @message = @{ $msg->{message_array} };
  return PLUGIN_EAT_NONE unless @message;

  if ($msg->{highlight}) {
    ## return if it's just the botnick
    return PLUGIN_EAT_NONE unless $message[1];
  
    ## we were highlighted -- might be an info3 cmd
    my %handlers = (
      'add' => '_info_add',
      'del' => '_info_del',
      'delete'  => '_info_del',
      'replace' => '_info_replace',
      'search'  => '_info_search',
      'dsearch' => '_info_dsearch',
      'display' => '_info_display',
      'about'   => '_info_about',
      'tell'    => '_info_tell',
      'infovars' => '_info_varhelp',
    );
    
    given (lc $message[1]) {
      when ([ keys %handlers ]) {
        ## this is apparently a valid command
        my @args = @message[2 .. $#message];
        my $method = $handlers{ $message[1] };
        if ( $self->can($method) ) {
          ## pass handlers $msg ref as first arg
          ## the rest is the remainder of the string
          ## (without highlight or command)
          ## ...which may be nothing, up to the handler to send syntax RPL
          my $resp = $self->$method($msg, @args);
          $core->send_event( 'send_message', 
            $context, $msg->{channel}, $resp ) if $resp;
          return PLUGIN_EAT_NONE
        } else {
          $core->log->warn($message[1]." is a valid cmd but method missing");
          return PLUGIN_EAT_NONE
        }
      }
      
      default {
        ## not an info3 cmd
        ## shift the highlight off and see if it's a match, below
        shift @message;
      }
    }
  }

  ## rejoin message
  my $str = join ' ', @message;

  ## check for matches
  my $match = $self->_info_match($str) || return PLUGIN_EAT_NONE;

  my $nick = $msg->{src_nick};
  my $channel = $msg->{channel};

  ## ~rdb, maybe? hand off to RDB.pm
  if ( index($match, '~') == 0) {
    my $rdb = (split ' ', $match)[0];
    $rdb = substr($rdb, 1);
    if ($rdb) {
      $core->log->debug("issuing rdb_triggered");
      $core->send_event( 'rdb_triggered',
        $context,
        $channel,
        $nick,
        lc($rdb),
        $match
      );
      return PLUGIN_EAT_NONE
    }
  }

  $core->log->debug("issuing info3_relay_string");
  
  $core->send_event( 'info3_relay_string', 
    $context, $channel, $nick, $match
  );

  return PLUGIN_EAT_NONE
}

sub Bot_info3_relay_string {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $channel = ${$_[1]};
  my $nick    = ${$_[2]};
  my $string  = ${$_[3]};

  ## format and send info3 response
  ## also received from RDB when handing off ~rdb responses
  
  return PLUGIN_EAT_NONE unless $string;

  $core->log->debug("info3_relay_string received; calling _info_format");
  
  my $resp = $self->_info_format($context, $nick, $channel, $string);

  ## if $resp is a +action, send ctcp action
  if ( index($resp, '+') == 0 ) {
    $resp = substr($resp, 1);
    $core->log->debug("Dispatching action -> $channel");
    $core->send_event('send_action', $context, $channel, $resp);
  } else {
    $core->log->debug("Dispatching msg -> $channel");
    $core->send_event('send_message', $context, $channel, $resp);
  }

  return PLUGIN_EAT_NONE
}


### Internal methods

sub _info_add {
  my ($self, $msg, @args) = @_;
  my $glob = shift @args;
  my $string = join ' ', @args;
  my $core = $self->{core};

  my $context = $msg->{context};
  my $nick = $msg->{src_nick};

  my $auth_user  = $core->auth_username($context, $nick);
  my $auth_level = $core->auth_level($context, $nick);

  my $pcfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $required = $pcfg->{RequiredLevels}->{AddTopic} // 2;
  unless ($auth_level >= $required) {
    return rplprintf( $core->lang->{RPL_NO_ACCESS},
      { nick => $nick },
    );
  }    

  unless ($glob && $string) {
    return rplprintf( $core->lang->{INFO_BADSYNTAX_ADD} );
  }
  
  ## lowercase
  $glob = lc $glob;

  if (exists $self->{Globs}->{$glob}) {
    ## topic already exists, use replace instead!
    return rplprintf( $core->lang->{INFO_ERR_EXISTS},
      {
        topic => $glob,
        nick => $nick,
      },
    );
  }

  ## set up a re
  my $re = glob_to_re_str($glob);
  ## anchored:
  $re = '^'.$re.'$' ;  
  
  ## add to db, keyed on glob:
  unless ($self->{DB}->dbopen) {
    $core->log->warn("DB open failure");
    return 'DB open failure'
  }
  $self->{DB}->put( $glob,
    {
      AddedAt => time(),
      AddedBy => $auth_user,
      Regex => $re,
      Response => $string,
    }
  );
  $self->{DB}->dbclose;

  ## invalidate info3 cache:
  $self->{Cache}->invalidate('info3');
  
  ## add to internal hashes:
  $self->{Regexes}->{$re} = $glob;
  $self->{Globs}->{$glob} = $re;

  ++$core->Provided->{info_topics};

  $core->log->debug("topic add: $glob ($re)");

  ## return RPL
  return rplprintf( $core->lang->{INFO_ADD},
    {
      topic => $glob,
      nick => $nick,
    },
  );
}

sub _info_del {
  my ($self, $msg, @args) = @_;
  my ($glob) = @args;
  my $core = $self->{core};
  
  my $context = $msg->{context};
  my $nick = $msg->{src_nick};

  my $auth_user  = $core->auth_username($context, $nick);
  my $auth_level = $core->auth_level($context, $nick);
  
  my $pcfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $required = $pcfg->{RequiredLevels}->{DelTopic} // 2;
  unless ($auth_level >= $required) {
    return rplprintf( $core->lang->{RPL_NO_ACCESS},
      { nick => $nick },
    );
  }    

  unless ($glob) {
    return rplprintf( $core->lang->{INFO_BADSYNTAX_DEL} );
  }
  
  
  unless (exists $self->{Globs}->{$glob}) {
    return rplprintf( $core->lang->{INFO_ERR_NOSUCH},
      {
        topic => $glob,
        nick  => $nick,
      }
    );
  }

  ## delete from db
  unless ($self->{DB}->dbopen) {
    $core->log->warn("DB open failure");
    return 'DB open failure'
  }
  $self->{DB}->del($glob);
  $self->{DB}->dbclose;
  
  $self->{Cache}->invalidate('info3');

  ## delete from internal hashes
  my $regex = delete $self->{Globs}->{$glob};
  delete $self->{Regexes}->{$regex};
  --$core->Provided->{info_topics};

  $core->log->debug("topic del: $glob ($regex)");
  
  return rplprintf( $core->lang->{INFO_DEL},
    {
      topic => $glob,
      nick  => $nick,
    },
  );  
}

sub _info_replace {
  my ($self, $msg, @args) = @_;
  my ($glob, @splstring) = @args;
  my $string = join ' ', @splstring;
  $glob = lc $glob;
  my $core = $self->{core};

  my $context = $msg->{context};
  my $nick = $msg->{src_nick};

  my $auth_user  = $core->auth_username($context, $nick);
  my $auth_level = $core->auth_level($context, $nick);
  
  my $pcfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $req_del = $pcfg->{RequiredLevels}->{DelTopic} // 2;
  my $req_add = $pcfg->{RequiredLevels}->{AddTopic} // 2;
  ## auth check for BOTH add and del reqlevels:
  unless ($auth_level >= $req_add && $auth_level >= $req_del) {
    return rplprintf( $core->lang->{RPL_NO_ACCESS},
      { nick => $nick },
    );
  }

  unless ($glob && $string) {
    return rplprintf( $core->lang->{INFO_BADSYNTAX_REPL} );
  }
  
  unless (exists $self->{Globs}->{$glob}) {
    return rplprintf( $core->lang->{INFO_ERR_NOSUCH},
      {
        topic => $glob,
        nick  => $nick,
      },
    );
  }

  $core->log->debug("replace called for $glob by $nick ($auth_user)");
  
  $self->{Cache}->invalidate('info3');

  unless ($self->{DB}->dbopen) {
    $core->log->warn("DB open failure");
    return 'DB open failure'
  }
  $self->{DB}->del($glob);
  $self->{DB}->dbclose;
  --$core->Provided->{info_topics};

  $core->log->debug("topic del (replace): $glob");
  
  my $regex = delete $self->{Globs}->{$glob};
  delete $self->{Regexes}->{$regex};

  my $re = glob_to_re_str($glob);
  $re = '^'.$re.'$' ;  

  unless ($self->{DB}->dbopen) {
    $core->log->warn("DB open failure");
    return 'DB open failure'
  }
  $self->{DB}->put( $glob,
    { 
      AddedAt => time(),
      AddedBy => $auth_user,
      Regex => $re,
      Response => $string,
    }
  );
  $self->{DB}->dbclose;

  $self->{Regexes}->{$re} = $glob;
  $self->{Globs}->{$glob} = $re;
  ++$core->Provided->{info_topics};

  $core->log->debug("topic add (replace): $glob ($re)");

  return rplprintf( $core->lang->{INFO_REPLACE},
    { topic => $glob, nick  => $nick }
  );
}

sub _info_tell {
  ## 'tell X about Y' syntax
  my ($self, $msg, @args) = @_;
  my $target = shift @args;
  my $core = $self->{core};

  unless ($target) {
    return rplprintf( $core->lang->{INFO_TELL_WHO} // "Tell who what?",
      { nick => $msg->{src_nick} }
    );
  }

  unless (@args) {
    return rplprintf( $core->lang->{INFO_TELL_WHAT}
      // "What should I tell $target about?" ,
        { nick => $msg->{src_nick}, target => $target }
    );
  }

  my $str_to_match;
  ## might be 'tell X Y':
  if (lc $args[0] eq 'about') {
    ## 'tell X about Y' syntax
    $str_to_match = join ' ', @args[1 .. $#args];
  } else {
    ## 'tell X Y' syntax
    $str_to_match = join ' ', @args;
  }

  ## find info match
  my $match = $self->_info_match($str_to_match);
  unless ($match) {
    return rplprintf( $core->lang->{INFO_DONTKNOW},
      { nick => $msg->{src_nick}, topic => $str_to_match }
    );
  }

  ## if $match is a RDB, send rdb_triggered and bail
  if ( index($match, '~') == 0) {
    my $rdb = (split ' ', $match)[0];
    $rdb = substr($rdb, 1);
    if ($rdb) {
      ## rdb_triggered will take it from here
      $core->send_event( 'rdb_triggered',
        $msg->{context},
        $msg->{channel},
        $target,
        lc($rdb),
        $match
      );
      return
    }
  }
    
  my $channel = $msg->{channel};
  
  $core->log->debug("issuing info3_relay_string for tell");

  $core->send_event( 'info3_relay_string', 
    $msg->{context}, $channel, $target, $match
  );

  return
}

sub _info_about {
  my ($self, $msg, @args) = @_;
  my ($glob) = @args;
  my $core = $self->{core};

  unless ($glob) {
    my $count = $core->Provided->{info_topics};
    return "$count info topics in database."
  }

  unless (exists $self->{Globs}->{$glob}) {
    return rplprintf( $core->lang->{INFO_ERR_NOSUCH},
      { topic => $glob, nick  => $msg->{src_nick} },
    );
  }

  ## parse and display addedat/addedby info
  $self->{DB}->dbopen || return 'DB open failure';
  my $ref = $self->{DB}->get($glob);
  $self->{DB}->dbclose;

  my $addedby = $ref->{AddedBy} || '(undef)';
  my $dt_addedat = DateTime->from_epoch( epoch => $ref->{AddedAt} );
  my $addedat = join ' ', $dt_addedat->date, $dt_addedat->time;
  my $str_len = length( $ref->{Response} );
  
  return rplprintf( $core->lang->{INFO_ABOUT},
    {
      nick  => $msg->{src_nick},
      topic => $glob,
      author => $addedby,
      date => $addedat,
      length => $str_len,
    }
  );
}

sub _info_display {
  ## return raw topic
  my ($self, $msg, @args) = @_;
  my ($glob) = @args;
  return unless $glob; # FIXME rpl?

  my $core = $self->{core};

  ## check if glob exists
  unless (exists $self->{Globs}->{$glob}) {
    return rplprintf( $core->lang->{INFO_ERR_NOSUCH},
      {
        topic => $glob,
        nick  => $msg->{src_nick},
      },
    );
  }
  
  ##  if so, show unparsed Response
  $self->{DB}->dbopen || return 'DB open failure';  
  my $ref = $self->{DB}->get($glob);
  $self->{DB}->dbclose;    
  my $response = $ref->{Response};
  return $response
}

sub _info_search {
  my ($self, $msg, @args) = @_;
  my ($str) = @args;
  
  my @matches = $self->_info_exec_search($str);
  return 'No matches' unless @matches;
  my $resp = "Matches: ";
  while ( length($resp) < 350 && @matches) {
    $resp .= ' '.shift(@matches);
  }
  return $resp;  
}

sub _info_exec_search {
  my ($self, $str) = @_;
  return 'Nothing to search' unless $str;
  my @matches;  
  for my $glob (keys %{ $self->{Globs} }) {
    push(@matches, $glob) unless index($glob, $str) == -1;
  }
  return @matches;
}

sub _info_dsearch {
  my ($self, $msg, @args) = @_;
  my $str = join ' ', @args;

  my $core = $self->{core};

  my $pcfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $req_lev = $pcfg->{RequiredLevels}->{DeepSearch} // 0;
  my $usr_lev = $core->auth_level($msg->{context}, $msg->{src_nick});
  unless ($usr_lev >= $req_lev) {
    return rplprintf( $core->lang->{RPL_NO_ACCESS},
      { nick => $msg->{src_nick} }
    );
  }

  my @matches = $self->_info_exec_dsearch($str);
  return 'No matches' unless @matches;
  my $resp = "Matches: ";
  while ( length($resp) < 350 && @matches) {
    $resp .= ' '.shift(@matches);
  }
  return $resp
}

sub _info_exec_dsearch {
  my ($self, $str) = @_;

  my $core = $self->{core};

  my $cache = $self->{Cache};
  my @matches = $cache->fetch('info3', $str) || ();

  ## matches found in searchcache
  return @matches if @matches;

  $self->{DB}->dbopen || return 'DB open failure';  
  for my $glob (keys %{ $self->{Globs} }) {
    my $ref = $self->{DB}->get($glob);
    unless (ref $ref eq 'HASH') {
      $core->log->warn("Inconsistent Info3? $glob appears to have no value");
      $core->log->warn("This could indicate database corruption!");
      next
    }
    my $resp_str = $ref->{Response};
    push(@matches, $glob) unless index($resp_str, $str) == -1;
  }
  $self->{DB}->dbclose;

  $cache->cache('info3', $str, [ @matches ]);

  return @matches;
}

sub _info_match {
  my ($self, $txt) = @_;
  my $core = $self->{core};
  ## see if text matches a glob in hash
  ## if so retrieve string from db and return it
  for my $re (keys %{ $self->{Regexes} }) {
    if ($txt =~ /$re/) {
      my $glob = $self->{Regexes}->{$re};
      $self->{DB}->dbopen || return 'DB open failure';
      my $ref = $self->{DB}->get($glob) || { };
      $self->{DB}->dbclose;
      my $str = $ref->{Response};
      return $str // 'Error retrieving info topic';
    }
  }
  return
}


sub _info_varhelp {
  my ($self, $msg) = @_;
  my $core = $self->{core};
  
  my $help =
     ' !~ = CmdChar, B~ = BotNick, C = Channel, H = UserHost, N = Nick,'
    .' P~ = Port, Q =~ Question, R~ = RandomNick, S~ = Server'
    .' t~ = unixtime, T~ = localtime, V~ = Version, W~ = Website'
  ;
  
  $core->send_event( 'send_notice',
    $msg->{context},
    $msg->{src_nick},
    $help
  );
  
  return ''
}

# Variable replacement / format
sub _info_format {
  my ($self, $context, $nick, $channel, $str) = @_;
  ## variable replacement for responses
  ## some of these need to pull info from context
  ## maintains oldschool darkbot6 variable format
  my $core = $self->{core};

  $core->log->debug("formatting text response ($context)");
  
  my $irc_obj = $core->get_irc_obj($context);
  return $str unless ref $irc_obj;

  my $ccfg = $core->get_core_cfg;
  my $cmdchar = $ccfg->{Opts}->{CmdChar};
  my @users   = $irc_obj->channel_list($channel) if $channel;
  my $random  = $users[ rand @users ] if @users;
  my $website = $core->url;

  my $vars = {
    '!' => $cmdchar,          ## CmdChar
    B => $irc_obj->nick_name, ## bot's nick for this context
    C => $channel,            ## channel
    H => $irc_obj->nick_long_form($irc_obj->nick_name) || '',
    N => $nick,               ## nickname
    P => $irc_obj->port,      ## remote port
    Q => $str,                ## question string
    R => $random,             ## random nickname
    S => $irc_obj->server,    ## current server
    t => time,                ## unixtime
    T => scalar localtime,    ## parsed time
    V => 'cobalt-'.$core->version,  ## version
    W => $core->url,          ## website
  };

  ## FIXME -- some color code syntax ?
  
  ##  1~ 2~ .. etc
  my $x = 0;
  for my $item (split ' ', $str) {
    ++$x;
    $vars->{$x} = $item;
  }

  ## var replace kinda like rplprintf
  ## call _info3repl()
  my $re = qr/((\S)~)/;
  $str =~ s/$re/__info3repl($1, $2, $vars)/ge;
  return $str
}
sub __info3repl {
  my ($orig, $match, $vars) = @_;
  return $orig unless defined $vars->{$match};
  return $vars->{$match}
}


1;
__END__

=pod


=cut
