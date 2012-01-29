package Cobalt::Plugin::Info3;
our $VERSION = '0.10';

## Handles glob-style "info" response topics
## Modelled on darkbot/cobalt1 behavior
## Commands:
##  <bot> add
##  <bot> del(ete)
##  <bot> replace
##  <bot> (d)search
##
## infodb is stored in memory to try to keep up with the 
## potentially rapid pace of IRC conversation.
##
## Uses YAML for serializing to on-disk storage.
##
## $infodb->{$glob} = {
##   Regex => $regex_from_glob
##   Response => $string
##   AddedBy => $username,
##   AddedAt => time,
## };
##
## Handles darkbot-style variable replacement

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use Cobalt::Utils qw/ :ALL /;
use Cobalt::Serializer;

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

  ## Compiled maps compiled REs to globs in Info
  $self->{Compiled} = { };
  ## it's automatically created when the db is read here:
  $self->{Info} = $self->_rw_db('read');

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
  my $msg = ${$_[1]};

  my $nick = $msg->{src_nick};
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
      'add' => '_info2_add',
      'del' => '_info2_del',
      'delete'  => '_info2_del',
      'search'  => '_info2_search',
      'dsearch' => '_info2_dsearch',      
    );
    
    given (lc $message[1]) {
      when ([ keys %handlers ]) {
        ## this is apparently a valid command
        my @args = $message[2 .. $#message];
        my $method = $handlers{ $message[1] };
        if ( $self->can($method) ) {
          ## pass handlers $msg ref as first arg
          ## the rest is the remainder of the string
          ## (without highlight or command)
          ## ...which may be nothing, up to the handler to send syntax RPL
          $resp = $self->$method($msg, @args);
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

  ## received from RDB when handing off ~rdb topics
  
  return PLUGIN_EAT_NONE unless $string;
  
  my $resp = $self->_info_format($context, $nick, $channel, $string);

  $core->send_event('send_message', $context, $channel, $string);

  return PLUGIN_EAT_NONE
}


### Internal methods

sub _info_add {
  my ($msg, @args) = @_;
  my ($topic, $string) = @args;
  my $core = $self->{core};

  unless ($topic && $string) {
    ## FIXME return syntax rpl
  }

  my $context = $msg->{context};
  my $nick = $msg->{src_nick};

  my $auth_user  = $core->auth_username($context, $nick);
  my $auth_level = $core->auth_level($context, $nick);
  ## FIXME auth check

  if (exists $self->{Info}->{$topic}) {
    ## FIXME return topic exists rpl
  }

  ## FIXME add to {Info} hash
  ## call write-out
  ## return RPL
}

sub _info_del {
  my ($msg, @args) = @_;
  my ($topic) = @args;
  my $core = $self->{core};
  
  unless ($topic) {
    ## FIXME syntax rpl
  }
  
  my $context = $msg->{context};
  my $nick = $msg->{src_nick};

  my $auth_user  = $core->auth_username($context, $nick);
  my $auth_level = $core->auth_level($context, $nick);
  
  ## FIXME auth check
  
  unless (exists $self->{Info}->{$topic}) {
    ## FIXME return topic doesn't exist rpl
  }
  
  ## FIXME delete from {Info} hash
  ## call write-out
  ## return RPL
}

sub _info_replace {
  my ($msg, @args) = @_;
  my ($topic, $string) = @args;
  my $core = $self->{core};

  unless ($topic && $string) {
    ## FIXME syntax rpl
  }
  
  my $context = $msg->{context};
  my $nick = $msg->{src_nick};
  my $auth_user = $core->auth_username($context, $nick);
  my $auth_level = $core->auth_level($context, $nick);
  
  ## FIXME auth check
  
  unless (exists $self->{Info}->{$topic}) {
    ## FIXME return topic doesn't exist rpl
  }
  
  ## FIXME delete and readd
  ## call writeout
  ## return RPL
}

sub _info_search {
  my ($msg, @args) = @_;
  my ($str) = @args;
  my @matches;  
  for my $glob (keys %{ $self->{Info} }) {
    push(@matches, $glob) unless index($glob, $str) == -1;
  }
  return @matches || 'No matches';
}

sub _info_dsearch {
  my ($msg, @args) = @_;
  ## dsearches w/ spaces are legit:
  my $str = join ' ', @args;
  my @matches;
  for my $glob (keys %{ $self->{Info} }) {
    my $resp_str = $self->{Info}->{$glob}->{Response};
    push(@matches, $glob) unless index($resp_str, $str) == -1;
  }
  return @matches || 'No matches';
}

sub _info_match {
  my ($self, $txt) = @_;
  ## see if text matches a glob in hash
  ## if so retrieve string from db and return it
  for my $re (keys %{ $self->{Compiled} }) {
    if ($txt =~ $re) {
      my $glob = $self->{Compiled}->{$re};
      my $str = $self->{Info}->{$glob}->{Response};
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
  my $website = $core->url;
  
  my $context_ref = $core->Servers->{$context} // return 'context failure';
  my $irc_obj = $context_ref->{Object};
  return $str unless ref $irc_obj;

  my $ccfg = $core->get_core_cfg;
  my $cmdchar = $ccfg->{Opts}->{CmdChar};
  my @users = $irc_obj->channel_list($channel) if $channel;
  my $random = $users[ rand @users ] if @users;

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


sub _rw_db {
   ## _rw_db('read')   _rw_db('write')
  my ($self, $op) = @_;
  return unless $op and $op ~~ [ qw/read write/ ];
  my $core = $self->{core};
  my $cfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $serializer = Cobalt::Serializer->new;
  my $var = $core->var;
  my $relative_to_var = $cfg->{Opts}->{InfoDB} // 'db/info3.yml';
  my $dbpath = $var ."/". $relative_to_var;
  given ($op) {
  
    when ("read") {
      my $db = $serializer->readfile($dbpath);
      if ($db && ref $db eq 'HASH') {
        ## compile into case-insensitive regexes
        for my $glob (keys %$db) {
          my $re = $db->{$glob}->{Regex} // glob_to_re_str($glob);
          ## compiled regex needs anchors
          ## (darkbot legacy)
          $re = qr/^${re}$/i;
          ## FIXME break into eventy loop?
          $self->{Compiled}->{$re} = $glob;
        }
        return $db
      } else {
        $core->log->warn("Could not read info3 DB.");
        $core->log->warn("Creating new info3 . . . ");
        return {}
      }
    }
    
    when ("write") {
      my $ref = $self->{Info};
      return 1 if $serializer->writefile($dbpath, $ref);
      $core->log->warn("Serializer failure, could not write $dbpath");
      return
    }

  }

}


1;
