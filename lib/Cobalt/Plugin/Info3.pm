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

## FIXME build on-disk db indexed by regex (DBM::Deep?)
##  in-memory; build regexes out of glob syntax (using Cobalt::Utils::glob_to_re_str)
##  store response & original glob string on-disk indexed by generated regexes
##  query on-disk db based on matched regex
## NOTE that glob_to_re_str doesn't start/end anchor on its own
##  will need to add anchors

## FIXME support legacy or rplprintf-style vars based on config Opt ...?

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use Cobalt::Utils qw/ :ALL /;
use Cobalt::Serializer;

## retval constants
use constant {
  SUCCESS  => 1,
  E_NOAUTH => 2,  # user not authorized
  E_EXISTS => 3,  # topic exists
  E_NOSUCH => 4,  # topic can't be found
  
};

sub new { bless( {}, shift ) }

sub Cobalt_register {
  my ($self, $core) = @_;
  $self->{core} = $core;
  $core->plugin_register($self, 'SERVER',
    [ 
      'public_msg',
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


sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};
  
  ## if this is a !cmd, discard it:
  return PLUGIN_EAT_NONE if $msg->{cmdprefix};

  ## FIXME check against hash of globs (in _match?)
  ## format and send response (via info3_relay_string ..?)

  return PLUGIN_EAT_NONE
}

sub Bot_info3_relay_string {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $channel = ${$_[1]};
  my $nick    = ${$_[2]};
  my $string  = ${$_[3]};

  ## received from RDB when handing off ~rdb topics
  ## FIXME _info_format and send
  
  return PLUGIN_EAT_NONE unless $string;
  
  my $resp = $self->_info_format($context, $nick, $channel, $string);

  $core->send_event('send_message', $context, $channel, $string);

  return PLUGIN_EAT_NONE
}




sub _handle_cmd {
  ## handle add/del/replace/search/dsearch
  ## convert retvals into RPLs as-necessary
}


### Internal methods

sub _info_add {

}

sub _info_del {

}

sub _info_replace {

}

sub _info_search {
  ## search/dsearch handler
}

sub _info_match {
  ## see if text matches a glob in hash
  ## if so retrieve string from db and return it
  
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
          $re = qr{$re}i;
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
      my $ref = $self->{InfoHash};
      return 1 if $serializer->writefile($dbpath, $ref);
      $core->log->warn("Serializer failure, could not write $dbpath");
      return
    }

  }

}


1;
