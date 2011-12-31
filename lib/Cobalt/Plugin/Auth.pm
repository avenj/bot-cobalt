package Cobalt::Plugin::Auth;

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;


## Utils:
use IRC::Utils qw/
  matches_mask
  parse_user
  lc_irc uc_irc eq_irc /;
use Cobalt::Utils qw/ mkpasswd passwdcmp /;

## Serialization:
use YAML::Syck;
use File::Slurp;

## Commands:
## PRIVMSG:
##   login <username> <passwd>
##   user add
##   user del
##   user list
##   user search

sub new { bless( {}, shift ) }

sub Cobalt_register {
  my ($self, $core) = @_;
  $self->{Core} = $core;
  $core->plugin_register($self, 'SERVER',
    [ 'private_msg' ],
  );

  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  ## FIXME clear any Auth states belonging to us
  $core->log->info("Unregistering core IRC plugin");
  return PLUGIN_EAT_NONE
}


sub Bot_private_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ $_[0] };

  my $resp;

  ## FIXME dispatch commands we care about to _dispatcher

  my @valid_cmds = qw/ login user /;
  my $command = $msg->{message_array}->[0] // return PLUGIN_EAT_NONE;
  $command = lc $command;

  if ($command ~~ @valid_cmds) {
    $self->log->debug("dispatching '$command' for ".$msg->{src_nick});
    $resp = $self->_cmd_$command($msg);
  }

  if ($resp) {
    $core->send_event( 'send_to_context',
      {
        context => $msg->{context},
        target => $msg->{src_nick},
        txt => $resp,
      }
    );    
  }

  return PLUGIN_EAT_NONE
}


### Frontends:

sub _cmd_login {
  my ($self, $msg) = @_;


}

sub _cmd_user {
  my ($self, $msg) = @_;

  ## user add
  ## user del
  ## user list
  ## user search
}



### Auth routines:

sub _user_login {
  my ($self, $username, $passwd, $host) = @_;
  my $core = $self->{Core};
  ## FIXME tag w/ pkg name so we can clear in _unregister

}

sub _user_logout {
  ## FIXME catch 'lost' users and handle logouts
}

sub _user_add {

}

sub _user_del {

}

sub _user_list {

}

sub _user_search {

}



### Access list mgmt methods
### (YAML frontend)

sub _read_access_list {

}

sub _write_access_list {

}


1;
