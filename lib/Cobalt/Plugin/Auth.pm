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
## Fairly basic access level system:
##
## - Users can have any numeric level.
##   Generally unauthenticated users will be level 0
##   Higher levels trump lower levels.
##   SuperUsers (auth.conf) get access level 9999.
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
## Loaded authdb exists in memory in $self->AccessList:
## ->AccessList = {
##   $context => {
##     $username => {
##       Masks => ARRAY,
##       Password => STRING (passwd hash),
##       Level => INT (9999 if superuser),
##       Flags => HASH,
##     },
##   },
## }
##
## Authenticated users exist in $core->State->{Auth}:
##
## {Auth}->{$context}->{$nickname} = {
##   Package => __PACKAGE__,
##   Username => STRING (identified username),
##    # 'Host' may not be reliable due to stupid cloaking cmds
##    # FIXME: query to check nicknames and update Host ?
##   Host => STRING (nick!user@host),
##   Level => INT (numeric level),
##   Flags => HASH (f.ex {SUPERUSER=>1} or other flags)
##   ## FIXME others? (Dis)AllowedChans ...?
## };
##
## Auth hash should be adjusted when nicknames change.
## This plugin tracks 'lost' identified users and clears as needed

use 5.12.1;
use strict;
use warnings;

use Moose;
use namespace::autoclean;

use Object::Pluggable::Constants qw/ :ALL /;

### Utils:
use IRC::Utils qw/
  matches_mask normalize_mask
  parse_user
  lc_irc uc_irc eq_irc /;
use Cobalt::Utils qw/ mkpasswd passwdcmp /;

### Serialization:
use YAML::Syck;
use Fcntl qw/:flock/;


### Constants, mostly for internal retvals:
use constant {
   ## _do_login RPL constants:
    SUCCESS   => 1,
    E_NOSUCH  => 2,
    E_BADPASS => 3,
    E_BADHOST => 4,
};


### Attributes
has 'core' => (
  is => 'rw',
  isa => 'Object',
);

has 'AccessList' => (
  is => 'rw',
  isa => 'HashRef',
  default => sub { {} },
);

has 'DB_Path' => (
  is => 'rw',
  isa => 'Str',
);


### Load/unload:
sub Cobalt_register {
  my ($self, $core) = @_;
  ## Set $self->core to make life easier on our internals:
  $self->core($core);

  my $pkg = __PACKAGE__;
  my $p_cfg = $core->cfg->{plugin_cf}->{$pkg};

  my $relative_path = $p_cfg->{Opts}->{AuthDB} || 'db/authdb.yml';
  my $authdb = $core->var ."/". $relative_path;
  $self->DB_Path($authdb);

  ## Read in main authdb:
  my $alist = $self->_read_access_list;
  unless ($alist) {
    die "initial _read_access_list failed, check log";
  }
  $self->AccessList( $alist );

  ## Read in configured superusers
  ## These will override existing usernames
  my $superusers = $p_cfg->{SuperUsers};
  my %su = ref $superusers eq 'HASH' ? %{$superusers} : ();
  for my $context (keys %su) {

    for my $user (keys $su{$context}) {
      ## Usernames automatically get lowercased
      ## per rfc1459 rules, aka CASEMAPPING=rfc1459
      ## (we probably don't even know the server's CASEMAPPING= yet)
      $user = lc_irc $user;
      ## AccessList entries for superusers:
      my $flags;
      ## Handle empty flag values:
      if (ref $su{$context}->{$user}->{Flags} eq 'HASH') {
        $flags = $su{$context}->{$user}->{Flags};
      } else { $flags = { }; }
      ## Set superuser flag:
      $flags->{SUPERUSER} = 1;
      $self->AccessList->{$context}->{$user} = {
        ## if you're lame enough to exclude a passwd, here's a random one:
        Password => $su{$context}->{$user}->{Password}
                     // $self->_mkpasswd(rand 10),
        ## SuperUsers are level 9999, to make life easier on plugins
        ## (allows for easy numeric level comparison)
        Level => 9999,
        ## ...standard Auth also provides a SuperUser flag:
        Flags => $flags,
      };

      ## Mask and Masks are both valid directives, Mask trumps Masks
      ## ...whether that's sane behavior or not is questionable
      ## (but it's what the comments in auth.conf specify)
      if (exists $su{$context}->{$user}->{Masks} &&
          !exists $su{$context}->{$user}->{Mask}) {
        $su{$context}->{$user}->{Mask} =
          $su{$context}->{$user}->{Masks};
      }

      ## the Mask specification in cfg may be an array or a string:
      if (ref $su{$context}->{$user}->{Mask} eq 'ARRAY') {
          $self->AccessList->{$context}->{$user}->{Masks} = [
            ## normalize masks into full, matchable masks:
            map { normalize_mask($_) } 
              @{ $su{$context}->{$user}->{Mask} }
          ];
        } else {
          $self->AccessList->{$context}->{$user}->{Masks} = [ 
            normalize_mask( $su{$context}->{$user}->{Mask} ) 
          ];
        }
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
  $core->log->info("Unregistering core IRC plugin");
  $self->_clear_self;
  return PLUGIN_EAT_NONE
}


### Bot_* events:
sub Bot_connected {
  my ($self, $core) = splice @_, 0, 2;
  ## Bot's freshly connected to a context
  ## Clear any auth entries for this pkg + context
  $self->_clear_self;
  return PLUGIN_EAT_NONE
}

sub Bot_disconnected {
  my ($self, $core) = splice @_, 0, 2;
  ## disconnect event
  $self->_clear_self;
  return PLUGIN_EAT_NONE
}

sub Bot_user_left {
  my ($self, $core) = splice @_, 0, 2;
  ## User left a channel
  ## If we don't share other channels, this user can't be tracked
  ## (therefore clear any auth entries for user belonging to us)
  my $context = $$_[0];
  my $channel = $$_[1]->{channel};
  my $nick = $$_[1]->{src_nick};

  ## FIXME if this is our nick that left the channel, query shared chan status of all auth'd users in this server context

  ## FIXME ask our irc component (from core->Servers) if we still share channels via _check_for_shared

  return PLUGIN_EAT_NONE
}

sub Bot_user_kicked {
  my ($self, $core) = splice @_, 0, 2;
  ## similar to user_left
  return PLUGIN_EAT_NONE
}

sub Bot_user_quit {
  my ($self, $core) = splice @_, 0, 2;
  my $context = $$_[0];
  my $nick = $$_[1]->{src_nick};
  ## User quit, clear relevant auth entries:
  $self->_do_logout($context, $nick);
  return PLUGIN_EAT_NONE
}

sub Bot_nick_changed {
  my ($self, $core) = splice @_, 0, 2;
  my $context = $$_[0];
  my $old = $$_[1]->{old};
  my $new = $$_[1]->{new};
  ## a nickname changed, adjust Auth accordingly:
  if (exists $core->State->{Auth}->{$context}->{$old}) {
    my $pkg = $core->State->{Auth}->{$context}->{$old}->{Package};
    if ($pkg eq __PACKAGE__) {  ## only adjust auths that're ours
      $core->State->{Auth}->{$context}->{$new} =
        delete $core->State->{Auth}->{$context}->{$old};
    }
  }
  return PLUGIN_EAT_NONE
}


sub Bot_private_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $context = $$_[0];
  my $msg = $$_[1];

  my $resp;

  my $command = $msg->{message_array}->[0] // return PLUGIN_EAT_NONE;
  $command = lc $command;

  ## simple method check/dispatch:
  my $method = "_cmd_".$command;
  if ( $self->can($method) ) {
    $self->log->debug("dispatching '$command' for ".$msg->{src_nick});
    $resp = $self->$method($context, $msg);
  }

  if ($resp) {
    $core->send_event( 'send_notice',
      {
        context => $context,
        target => $msg->{src_nick},
        txt => $resp,
      }
    );    
  }

  return PLUGIN_EAT_NONE
}


### Frontends:

sub _cmd_login {
  ## interact with _do_login and set up response RPLs
  ## _do_login does the heavy lifting, we just talk to the user.
  my ($self, $context, $msg) = @_;
  my $l_user = $msg->{message_array}->[1] // undef;
  my $l_pass = $msg->{message_array}->[2] // undef;
  my $origin = $msg->{src};
  my $nick = $msg->{src_nick};

  unless (defined $l_user && defined $l_pass) {
    ## pointless use of sprintf in case we add args later:
    return sprintf($self->core->lang->{AUTH_BADSYN_LOGIN});
  }

  ## NOTE: usernames in accesslist are stored lowercase per rfc1459 rules:
  $l_user = lc_irc($l_user);

  ## IMPORTANT:
  ## nicknames (for auth hash) remain unmolested
  ## case changes are managed by tracking actual nickname changes
  ## (that way we don't have to worry about it when checking access levels)

  ## _do_login returns constants we can translate into a langset RPL:
  ## SUCCESS E_NOSUCH E_BADPASS E_BADHOST
  my $retval = $self->_do_login($context, $nick, $l_user, $l_pass, $origin);
  my $resp;
  given ($retval) {
    when (SUCCESS) {
      ## AUTH_SUCCESS $username $level
      $resp = sprintf( $self->core->lang->{AUTH_SUCCESS},
        $l_user,
        $self->core->State->{Auth}->{$context}->{$nick}->{Level},
      );
    }
    when (E_NOSUCH) {
      $resp = sprintf( $self->core->lang->{AUTH_FAIL_NO_SUCH}, $l_user );
    }
    when (E_BADPASS) {
      $resp = sprintf( $self->core->lang->{AUTH_FAIL_BADPASS}, $l_user );
    }
    when (E_BADHOST) {
      $resp = sprintf( $self->core->lang->{AUTH_FAIL_BADHOST}, $l_user );
    }
  }

  return $resp  ## return a response to the _private_msg handler
}

sub _cmd_chpass {
  my ($self, $context, $msg) = @_;

  ## FIXME self chpass for logged in users
  ## (_cmd_user has a chpass for administrative use)

}

sub _cmd_user {
  my ($self, $context, $msg) = @_;

  ## user add
  ## user del
  ## user list
  ## user search
  my $cmd = lc( $msg->{message_array}->[1] // '');

  my $resp;

  unless ($cmd) {
    ## FIXME
  }

  ## FIXME method dispatch like the _cmd_ dispatcher above
  ##   pass args unmolested?
  ##   
  my $method = "_user_".$cmd;

  return $resp;
}



### Auth routines:

sub _do_login {
  ## backend handler for _cmd_login, returns constants
  ## we can be fairly sure syntax is correct from here
  ## also, $username should've already been normalized via lc_irc:
  my ($self, $context, $nick, $username, $passwd, $host) = @_;

  ## note that this'll autoviv a nonexistant AccessList context
  ## (which is alright, but it's good to be aware of it)
  unless (exists $self->AccessList->{$context}->{$username}) {
    $self->log->debug("[$context] authfail; no such user: $username ($host)");
    ## auth_failed_login ($context, $nick, $username, $host, $error_str)
    $self->core->send_event( 'auth_failed_login',
      $context,
      $nick,
      $username,
      $host,
      'NO_SUCH_USER',
    );
    return E_NOSUCH
  }

  ## check username/passwd/host against AccessList:
  my $user_record = $self->AccessList->{$context}->{$username};
  ## masks should be normalized already:
  my @matched_masks;
  for my $mask (@{ $user_record->{Masks} }) {
    push(@matched_masks, $mask) if matches_mask($mask, $host);
  }

  unless (@matched_masks) {
    $self->log->debug("[$context] authfail; no host match: $username ($host)");
    $self->core->send_event( 'auth_failed_login',
      $context,
      $nick,
      $username,
      $host,
      'BAD_HOST',
    );
    return E_BADHOST
  }

  unless ( passwdcmp($passwd, $user_record->{Password}) ) {
    $self->log->debug("[$context] authfail; bad passwd: $username ($host)");
    $self->core->send_event( 'auth_failed_login',
      $context,
      $nick,
      $username,
      $host,
      'BAD_PASS',
    );
    return E_BADPASS
  }

  ## deref from accesslist and initialize our Auth hash for this nickname:
  my $level = $user_record->{Level};
  my %flags = %{ $user_record->{Flags} // {} };
  $self->core->State->{Auth}->{$context}->{$nick} = {
    Package => __PACKAGE__,
    Username => $username,
    Host => $host,
    Level => $level,
    Flags => \%flags,
  };

  $self->log->debug(
    "[$context] successful auth: $username (lev $level) ($host)"
  );

  ## send Bot_auth_user_login ($context, $nick, $host, $username, $lev):
  $self->core->send_event( 'auth_user_login',
    $context,
    $nick,
    $host,
    $username,
    $level,
  );

  return SUCCESS
}

sub _do_logout {
  ## catch 'lost' users and handle logouts
  ## send a logout event in addition to clearing auth hash
  ## returns the deleted user auth hash (or nothing)
  my ($self, $context, $nick) = @_;
  my $core = $self->core;
  if (exists $core->State->{Auth}->{$context}->{$nick}) {
    my $pkg = $core->State->{Auth}->{$context}->{$nick}->{Package};
    if ($pkg eq __PACKAGE__) {
      ## FIXME accessors?
      my $host = $core->State->{Auth}->{$context}->{$nick}->{Host};
      my $username = $core->State->{Auth}->{$context}->{$nick}->{Username};
      my $level =  $core->State->{Auth}->{$context}->{$nick}->{Level};
      ## Bot_auth_user_logout ($context, $nick, $host, $username, $lev, $pkg):
      $self->core->send_event( 'auth_user_logout',
        $context,
        $nick,
        $host,
        $username,
        $level,
        $pkg,
      );
      return delete $core->State->{Auth}->{$context}->{$nick};
    }
  }
  return
}

sub _user_add {
  ## add users to AccessList and call a list sync
}

sub _user_delete { _user_del(@_) }
sub _user_del {
  ## delete users from AccessList and call a list sync
}

sub _user_list {

}

sub _user_search {

}

sub _user_chflags {

}

sub _user_chmask {
  ## [+/-]mask syntax so as not to be confused with user del (much)
  ## FIXME normalize masks before adding ?
}

sub _user_chpass {
  ## superuser (or configurable level.. ?) chpass ability
}


### Utility methods:

sub _check_for_shared {
  ## $self->_check_for_shared( $context, $nickname );
  ##
  ## Query the IRC component to see if we share channels with a user.
  ## Actually just a simple frontend to get_irc_obj & PoCo::IRC::State
  ##
  ## Returns boolean true or false.
  ## Typically called after either the bot or a user leave a channel.
  ##
  ## Tells Auth whether or not we can sanely track this user.
  ## If we don't share channels it's difficult to get nick change
  ## notifications and generally validate authenticated users.
  my ($self, $context, $nick) = @_;
  my $irc = $self->core->get_irc_obj( $context );
  my @shared = $irc->nick_channels( $nick );
  return @shared ? 1 : 0 ;
}

sub _clear_self {
  my ($self) = @_;
  ## $self->clear_self()
  ## Clear any $core->{Auth} states belonging to us
  for my $context (keys %{ $self->core->{Auth} }) {

    for my $nick (keys %{ $self->core->{Auth}->{$context} }) {
      my $pkg = $self->core->{Auth}->{$context}->{$nick}->{Package};
      if ($pkg eq __PACKAGE__) {
        $self->core->log->debug("cleared auth: $nick ($context)");
        delete $self->core->{Auth}->{$context}->{$nick};
      }
    }

  }
}

sub _mkpasswd {
  my ($self, $passwd) = @_;
  return unless $passwd;
  ## $self->_mkpasswd( $passwd );
  ## simple frontend to Cobalt::Utils::mkpasswd()
  ## handles grabbing cfg opts for us:
  my $pkg = __PACKAGE__;
  my $cfg = $self->core->cfg->{plugin_cf}->{$pkg};
  my $method = $cfg->{Method} // 'bcrypt';
  my $bcrypt_cost = $cfg->{Bcrypt_Cost} // '08';
  return mkpasswd($passwd, $method, $bcrypt_cost);
}



### Access list mgmt methods
### (YAML frontend)

sub _read_access_list {
  my ($self, $authdb) = @_;
  ## Default to $self->DB_Path
  $authdb = $self->DB_Path unless $authdb;
  my $core = $self->core;
  ## read authdb, spit out hash

  unless (-f $authdb) {
    $core->log->debug("did not find authdb at $authdb");
    $core->log->info("No existing authdb, creating empty access list.");
    return { }
  }

  open(my $db_in, '<', $authdb)
    or (
      $core->log->emerg("Open failed in _read_access_list: $!")
      and return
  );
  flock($db_in, LOCK_SH)
    or (
      $core->log->emerg("LOCK_SH failed in _read_access_list: $!")
      and return
  );
  my $yaml = <$db_in>;

  flock($db_in, LOCK_UN)
    or $core->log->warn("LOCK_UN failed in _read_access_list: $!");
  close($db_in);

  utf8::encode($yaml);

  my $accesslist = Load $yaml;

  return $accesslist
}

sub _write_access_list {
  my ($self, $authdb, $alist) = @_;
  $authdb = $self->DB_Path unless $authdb;
  $alist  = $self->AccessList unless $alist;
  my $core = $self->core;

  ## we don't want to write superusers back out:
  my %hash = %$alist;
  for my $context (keys %hash) {
    for my $user (keys %{$hash{$context}}) {
      if ($hash{$context}->{$user}->{Flags}->{SUPERUSER}) {
        delete $hash{$context}->{$user};
      }
    }
    ## don't need to write empty contexts either:
    delete $hash{$context} unless scalar keys %{ $hash{$context} };
  }

  ## don't need to write empty access lists to disk ...
  return unless scalar keys %hash;

  my $yaml = Dump \%hash;

  utf8::decode($yaml);

  open(my $db_out, '>>', $authdb)
    or (
      $core->log->emerg("Open failed in _write_access_list: $!")
      and return
  );
  flock($db_out, LOCK_EX | LOCK_NB)
    or ( 
      $core->log->emerg("LOCK_EX failed in _write_access_list: $!")
      and return
  );

  seek($db_out, 0, 0);
  truncate($db_out, 0);
  print $db_out $yaml;

  flock($db_out, LOCK_UN)
    or (
      $core->log->emerg("LOCK_UN failed in _write_access_list: $!")
      and return
  );
  close($db_out);

  my $pkg = __PACKAGE__;
  my $p_cfg = $core->cfg->{plugin_cf}->{$pkg};
  my $perms = $p_cfg->{Opts}->{AuthDB_Perms} // 0600;
  chmod($perms, $authdb);
}


__PACKAGE__->meta->make_immutable;
no Moose; 1;
__END__

=pod

=head1 NAME

Cobalt::Plugin::Auth -- standard access control plugin

=head1 DESCRIPTION

This plugin provides the standard authorization and access control 
functionality for B<Cobalt>.


=head1 CONFIGURATION

=head2 plugins.conf

=head2 auth.conf


=head1 EMITTED EVENTS


=head1 ACCEPTED EVENTS


=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
