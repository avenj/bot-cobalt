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
## $infodb = {
##   trigger => $regex
##   response => $string
##
## };
##
## Handles variable replacement

## FIXME build on-disk db indexed by regex (DBM::Deep?)
##  in-memory; build regexes out of glob syntax (using Cobalt::Utils::glob_to_re_str)
##  store response & original glob string on-disk indexed by generated regexes
##  query on-disk db based on matched regex
## NOTE that glob_to_re_str doesn't start/end anchor on its own
##  will need to add anchors

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use Cobalt::Utils qw/ color rplprintf /;
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

  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  $core->log->info("Unregistering core IRC plugin");
  return PLUGIN_EAT_NONE
}


sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};
  
  ## if this is a !cmd, discard it:
  return PLUGIN_EAT_NONE if $msg->{cmdprefix};


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
  ## FIXME get entire msg .. ?
  ## see if text matches
  ## if topic contains a rdb, send rdb_triggered to talk to RDB.pm
}

sub _info_format {
  my ($self, $context, $nick, $channel, $str) = @_;
  ## variable replacement for responses
  ## some of these need to pull info from context
  ## FIXME reference cobalt1 set
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
  ## maintains darkbot legacy syntax
  sub _info3repl {
    my ($orig, $match, $vars) = @_;
    return $orig unless defined $vars->{$match};
    return $vars->{$match}
  }
  my $re = qr/((\S)~)/;
  $str =~ s/$re/_info3repl($1, $2, $vars)/ge;
  return $str
}


### Serialization

sub _write_infodb {

}

sub _read_infodb {

}


1;
