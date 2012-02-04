package Cobalt::Plugin::Info3;
our $VERSION = '0.12';


## FIXME db open err checks
## FIXME serializer dump cmd?


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

use Object::Pluggable::Constants qw/ :ALL /;

use Cobalt::Utils qw/ :ALL /;

use Cobalt::DB;

sub new { bless( {}, shift ) }

sub Cobalt_register {
  my ($self, $core) = @_;
  $self->{core} = $core;
  $core->plugin_register($self, 'SERVER',
    [ 
      'public_msg',
      'public_cmd_info3',
      'info3_relay_string',
    ],
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
  for my $glob ($self->{DB}->keys) {
    my $ref = $self->{DB}->get($glob);
    my $regex = $ref->{Regex};
    $self->{Globs}->{$glob} = $regex;
    $self->{Regexes}->{$regex} = $glob;
  }
  $self->{DB}->dbclose;

  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  $core->log->info("Unregistering Info plugin");
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_info3 {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg     = ${$_[1]};

  my $nick    = $msg->{src_nick};
  my $channel = $msg->{channel};
  
  my @message = @{ $msg->{message_array} };
  unless (@message) {  
    ## FIXME bad syntax rpl on empty @message
    
    return PLUGIN_EAT_ALL
  }
  
  my $cmd = lc $message[0];
  my $resp;

  ## FIXME handler like public_msg
  
  $core->send_event( 'send_message', $context, $channel, $resp )
    if $resp;
  
  return PLUGIN_EAT_ALL
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
      'search'  => '_info_search',
      'dsearch' => '_info_dsearch',
      ## FIXME 'display'
      ## FIXME 'about'
      ## FIXME 'tell X about Y'
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
            $context, $msg->{channel}, $resp) if $resp;
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
  ## alsoreceived from RDB when handing off ~rdb topics
  
  return PLUGIN_EAT_NONE unless $string;

  $core->log->debug("info3_relay_string received; calling _info_format");
  
  my $resp = $self->_info_format($context, $nick, $channel, $string);

  $core->send_event('send_message', $context, $channel, $resp);

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

  ## set up a re:
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
  
  ## add to internal hashes:
  $self->{Regexes}->{$re} = $glob;
  $self->{Globs}->{$glob} = $re;

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
  
  ## delete from internal hashes
  my $regex = delete $self->{Globs}->{$glob};
  delete $self->{Regexes}->{$regex};

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
  my ($glob, $string) = @args;
  my $core = $self->{core};

  my $context = $msg->{context};
  my $nick = $msg->{src_nick};
  my $auth_user = $core->auth_username($context, $nick);
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
  
  unless ($self->{DB}->dbopen) {
    $core->log->warn("DB open failure");
    return 'DB open failure'
  }
  $self->{DB}->del($glob);
  $self->{DB}->dbclose;
  
  my $regex = delete $self->{Globs}->{$glob};
  delete $self->{Regexes}->{$regex};

  return rplprintf( $core->lang->{INFO_REPLACE},
    {
      topic => $glob,
      nick  => $nick,
    }
  );
}

sub _info_search {
  my ($self, $msg, @args) = @_;
  my ($str) = @args;
  my @matches;  
  for my $glob (keys %{ $self->{Globs} }) {
    push(@matches, $glob) unless index($glob, $str) == -1;
  }
  return @matches || 'No matches';
}

sub _info_dsearch {
  my ($self, $msg, @args) = @_;
  ## dsearches w/ spaces are legit:
  my $str = join ' ', @args;
  my @matches;

  my $core = $self->{core};
  my $pcfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $req_lev = $pcfg->{RequiredLevels}->{DeepSearch} // 0;
  my $usr_lev = $core->auth_level($msg->{context}, $msg->{src_nick});
  unless ($usr_lev >= $req_lev) {
    return rplprintf( $core->lang->{RPL_NO_ACCESS},
      { nick => $msg->{src_nick} }
    );
  }

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

  return @matches || 'No matches';
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
  my @users = $irc_obj->channel_list($channel) if $channel;
  my $random = $users[ rand @users ] if @users;
  my $website = $core->url;

  my $vars = {
    '!' => $cmdchar,          ## CmdChar
    B => $irc_obj->nick_name, ## bot's nick for this context
    C => $channel,            ## channel
    H => $irc_obj->nick_long_form($nick), # n!u@h
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
