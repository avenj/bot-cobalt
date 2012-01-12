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

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;


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
    [ 'public_msg' ],
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
  ## see if text matches
}

sub _info_format {
  ## variable replacement for responses
}


### Serialization

sub _write_infodb {

}

sub _read_infodb {

}


1;
