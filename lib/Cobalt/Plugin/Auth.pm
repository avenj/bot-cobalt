package Cobalt::Plugin::Auth;
our $VERSION = '0.10';

## "Standard" Auth module
##
## Commands:
## PRIVMSG:
##    login <username> <passwd>
##    chpass <oldpass> <newpass>
##    user add
##    user del
##    user list
##    user search
##    user chpass
##
##
## Very basic access level system:
##
## - Users can have any numeric level.
##   Generally unauthenticated users will be level 0
##   Higher levels trump lower levels.
##
## - SuperUsers (auth.conf) always trumps other access levels.
##
## - Plugins determine required levels for their respective commands
##
##
## Authenticate via 'login <username> <passwd>' in PRIVMSG
## Users can be managed online via the PRIVMSG 'user' command
##
## Passwords are hashed via bcrypt and stored in YAML
## Location of the authdb is determined by auth.conf
##
## Authenticated users exist in $core->State->{Auth}:
## {Auth}->{$context}->{$nickname}
## This plugin tracks 'lost' identified users and clears as needed

use 5.12.1;
use strict;
use warnings;

use Moose;

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

use namespace::autoclean;

has 'core' => (
  is => 'rw',
  isa => 'Object',
);

has 'AccessList' => (
  is => 'rw',
  isa => 'HashRef',
  default => sub { {} },
);

sub Cobalt_register {
  my ($self, $core) = @_;
  $self->core($core);

  my $pkg = __PACKAGE__;
  my $p_cfg = $core->cfg->{plugin_cf}->{$pkg};

  my $relative_path = $p_cfg->{Opts}->{AuthDB} // 'db/authdb.yml';
  my $authdb = $core->var ."/". $relative_path;

  $self->AccessList( $self->_read_access_list($authdb) );

  ## Read in configured superusers
  ## These will override existing usernames
  ## FIXME case sensitivity ...?
  for my $context (keys $p_cfg->{SuperUsers}) {
    for my $user (keys $p_cfg->{SuperUsers}->{$context}) {
      ## FIXME set up AccessList entries
    }
  }

  $core->plugin_register($self, 'SERVER',
    [
      'connected',
      'disconnected',
      'user_left',
      'user_kicked',
      'user_quit',
      'nick_changed',
      'private_msg',
    ],
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


sub Bot_connected {
  ## Bot's freshly connected to a context
  ## Clear any auth entries for this pkg + context
}

sub Bot_disconnected {
  ## disconnect event, clear auth entries for this pkg + context
}

sub Bot_user_left {
  ## User left a channel
  ## If we don't share other channels, this user can't be tracked
  ## (therefore clear any auth entries for user belonging to us)
}

sub Bot_user_kicked {
  ## similar to user_left
}

sub Bot_user_quit {
  ## User quit, clear relevant auth entries
}

sub Bot_nick_changed {
  ## nickname changed, adjust Auth accordingly
}


sub Bot_private_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ $_[0] };

  my $resp;

  my $command = $msg->{message_array}->[0] // return PLUGIN_EAT_NONE;
  $command = lc $command;

  ## simple method check/dispatch:
  my $method = "_cmd_".$command;
  if ( $self->can($method) ) {
    $self->log->debug("dispatching '$command' for ".$msg->{src_nick});
    $resp = $self->$method($msg);
  }

  if ($resp) {
    $core->send_event( 'send_notice',
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
  my $context = $msg->{context};

  my $l_user = $msg->{message_array}->[1] // undef;
  my $l_pass = $msg->{message_array}->[2] // undef;

  unless (defined $l_user && defined $l_pass) {
    ## return bad syntax RPL
  }

  ## interact with _user_login and set up responses

}

sub _cmd_chpass {
  my ($self, $msg) = @_;
  my $context = $msg->{context};

  ## FIXME self chpass for logged in users
  ## (_cmd_user has a chpass for administrative use)

}

sub _cmd_user {
  my ($self, $msg) = @_;

  ## user add
  ## user del
  ## user list
  ## user search
  my @valid = qw/ add del delete list search chpass /;
  my $cmd = lc( $msg->{message_array}->[1] // '');

  my $context = $msg->{context};

  my $resp;

  if (! $cmd) {
    ## FIXME return bad syntax RPL
  }

  unless ($cmd ~~ @valid) {
    ## FIXME return invalid command/bad syntax RPL
  }
    
  given ($cmd) {
    when ("add") {

    }

    when (/^del(ete)?$/) {

    }

    when ("list") {

    }

    when ("search") {

    }

    when ("chpass") {

    }
  }

  return $resp;
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

sub _user_chpass {

}



### Access list mgmt methods
### (YAML frontend)

sub _read_access_list {
  my ($self, $authdb) = @_;
  ## read authdb, spit out hash
}

sub _write_access_list {

}


__PACKAGE__->meta->make_immutable;
no Moose; 1;
