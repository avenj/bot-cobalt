package Cobalt::Plugin::Auth;
our $VERSION = '0.16';

## FIXME handle context 'ALL'

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

use Moose;
use namespace::autoclean;

use Cobalt::Common;

use Cobalt::Serializer;


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
  my ($self, $core) = splice @_, 0, 2;
  ## Set $self->core to make life easier on our internals:
  $self->core($core);

  my $p_cfg = $core->get_plugin_cfg( $self );

  my $relative_path = $p_cfg->{Opts}->{AuthDB} || 'db/authdb.yml';
  my $authdb = $core->var ."/". $relative_path;
  $self->DB_Path($authdb);

  ## Read in main authdb:
  my $alist = $self->_read_access_list;
  unless ($alist) {
    die "initial _read_access_list failed, check log";
  }
  $self->AccessList( $alist );

  ## Read in configured superusers to AccessList
  ## These will override existing usernames
  my $superusers = $p_cfg->{SuperUsers};
  my %su = ref $superusers eq 'HASH' ? %{$superusers} : ();
  SERVER: for my $context (keys %su) {

    USER: for my $user (keys $su{$context}) {
      ## Usernames on accesslist automatically get lowercased
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
      if (exists $su{$context}->{$user}->{Masks} 
          && !exists $su{$context}->{$user}->{Mask} ) {
        $su{$context}->{$user}->{Mask} = 
          delete $su{$context}->{$user}->{Masks};
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

      $core->log->debug("added superuser: $user (context: $context)");
    } ## USER

  } ## SERVER

  $core->plugin_register($self, 'SERVER',
    [
      'connected',
      'disconnected',

      'user_quit',
      'user_left',
      'self_left',

      'self_kicked',
      'user_kicked',

      'nick_changed',

      'private_msg',
    ],
  );

  ## clear any remaining auth states.
  ## (assuming the plugin unloaded cleanly, there should be none)
  $self->_clear_all;

  $core->log->info("$VERSION loaded");

  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistering core IRC plugin");
  ## FIXME save authdb?
  $self->_clear_all;
  return PLUGIN_EAT_NONE
}


### Bot_* events:
sub Bot_connected {
  my ($self, $core) = splice @_, 0, 2;
  ## Bot's freshly connected to a context
  ## Clear any auth entries for this pkg + context
  my $context = ${$_[0]};
  $self->_clear_context($context);
  return PLUGIN_EAT_NONE
}

sub Bot_disconnected {
  my ($self, $core) = splice @_, 0, 2;
  ## disconnect event
  my $context = ${$_[0]};

  $self->_clear_context($context);

  return PLUGIN_EAT_NONE
}

sub Bot_user_left {
  my ($self, $core) = splice @_, 0, 2;
  ## User left a channel
  ## If we don't share other channels, this user can't be tracked
  ## (therefore clear any auth entries for user belonging to us)
  my $context = ${$_[0]};
  my $left    = ${$_[1]};

  my $channel = $left->{channel};
  my $nick    = $left->{src_nick};

  ## Call _remove_if_lost to see if we can still track this user:
  $self->_remove_if_lost($context, $nick);

  return PLUGIN_EAT_NONE
}

sub Bot_self_left {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $channel = ${$_[1]};
  ## The bot left a channel. Check auth status of all users.
  ## This method may be unreliable on nets w/ busted CASEMAPPING=
  $self->_remove_if_lost($context);
  return PLUGIN_EAT_NONE
}

sub Bot_self_kicked {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  $self->_remove_if_lost($context);
  return PLUGIN_EAT_NONE
}

sub Bot_user_kicked {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $nick    = ${$_[1]}->{src_nick};
  $self->_remove_if_lost($context, $nick);
  return PLUGIN_EAT_NONE
}

sub Bot_user_quit {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $nick    = ${$_[1]}->{src_nick};
  ## User quit, clear relevant auth entries
  ## We can call _do_logout directly here:
  $self->_do_logout($context, $nick);
  return PLUGIN_EAT_NONE
}

sub Bot_nick_changed {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $old = ${$_[1]}->{old};
  my $new = ${$_[1]}->{new};
  ## a nickname changed, adjust Auth accordingly:
  if (exists $core->State->{Auth}->{$context}->{$old}) {
    my $pkg = $core->State->{Auth}->{$context}->{$old}->{Package};
    if ($pkg eq __PACKAGE__) {  ## only adjust auths that're ours
      $core->log->debug("adjusting authnicks; $old -> $new");
      $core->State->{Auth}->{$context}->{$new} =
        delete $core->State->{Auth}->{$context}->{$old};
    }
  }
  return PLUGIN_EAT_NONE
}


sub Bot_private_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};

  my $resp;

  my $command = $msg->{message_array}->[0] // return PLUGIN_EAT_NONE;
  $command = lc $command;

  ## simple method check/dispatch:
  my $method = "_cmd_".$command;
  if ( $self->can($method) ) {
    $core->log->debug("dispatching '$command' for ".$msg->{src_nick});
    $resp = $self->$method($context, $msg);
  }

  if ($resp) {
    my $target = $msg->{src_nick};
    $core->log->debug("dispatching send_notice to $target");
    $core->send_event( 'send_notice', $context, $target, $resp );
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
    ## bad syntax resp, currently takes no args ...
    return rplprintf( $self->core->lang->{AUTH_BADSYN_LOGIN} );
  }

  ## NOTE: usernames in accesslist are stored lowercase per rfc1459 rules:
  $l_user = lc_irc $l_user;

  ## IMPORTANT:
  ## nicknames (for auth hash) remain unmolested
  ## case changes are managed by tracking actual nickname changes
  ## (that way we don't have to worry about it when checking access levels)

  ## _do_login returns constants we can translate into a langset RPL:
  ## SUCCESS E_NOSUCH E_BADPASS E_BADHOST

  ## FIXME: E_NOCHANS (and check for shared channels in order to allow a login)
  my $retval = $self->_do_login($context, $nick, $l_user, $l_pass, $origin);
  my $rplvars = {
    context => $context,
    src => $origin,
    nick => $nick,
    user => $l_user,
  };
  my $resp;
  given ($retval) {
    when (SUCCESS) {
      ## add level to rplvars:
      $rplvars->{lev} = $self->core->auth_level($context, $nick);
      $resp = rplprintf( $self->core->lang->{AUTH_SUCCESS}, $rplvars );
    }
    when (E_NOSUCH) {
      $resp = rplprintf( $self->core->lang->{AUTH_FAIL_NO_SUCH}, $rplvars );
    }
    when (E_BADPASS) {
      $resp = rplprintf( $self->core->lang->{AUTH_FAIL_BADPASS}, $rplvars );
    }
    when (E_BADHOST) {
      $resp = rplprintf( $self->core->lang->{AUTH_FAIL_BADHOST}, $rplvars );
    }
  }

  return $resp  ## return a response to the _private_msg handler
}

sub _cmd_chpass {
  my ($self, $context, $msg) = @_;
  ## 'self' chpass for logged-in users
  ##    chpass OLD NEW
  my $nick = $msg->{src_nick};
  my $auth_for_nick = $self->core->auth_username($context, $nick);
  unless ($auth_for_nick) {
    return rplprintf( $self->core->lang->{RPL_NO_ACCESS},
      { nick => $nick },
    );
  }
  
  my $passwd_old = $msg->{message_array}->[1];
  my $passwd_new = $msg->{message_array}->[2];
  unless ($passwd_old && $passwd_new) {
    return rplprintf( $self->core->lang->{AUTH_BADSYN_CHPASS} );
  }
  
  my $user_rec = $self->AccessList->{$context}->{$auth_for_nick};
  my $stored_pass = $user_rec->{Password};
  unless ( passwdcmp($passwd_old, $stored_pass) ) {
    return rplprintf( $self->core->lang->{AUTH_CHPASS_BADPASS},
      {
        context => $context,
        nick => $nick,
        user => $auth_for_nick,
        src => $msg->{src},
      }
    );
  }
  
  my $new_hashed = $self->_mkpasswd($passwd_new);
  $user_rec->{Password} = $new_hashed;
  return rplprintf( $self->core->lang->{AUTH_CHPASS_SUCCESS},
    {
      context => $context,
      nick => $nick,
      user => $auth_for_nick,
      src => $msg->{src},
    }
  );
}

sub _cmd_whoami {
  my ($self, $context, $msg) = @_;
  ## return current auth status
  my $nick = $msg->{src_nick};
  my $auth_lev = $self->core->auth_level($context, $nick);
  my $auth_usr = $self->core->auth_username($context, $nick) 
                 // 'Not Authorized';
  return rplprintf( $self->core->lang->{AUTH_STATUS},
    {
      username => $auth_usr,
      nick => $nick,
      lev  => $auth_lev,
    }
  );  
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
    ## FIXME bad syntax rpl
  }

  ## FIXME method dispatch like the _cmd_ dispatcher above
  ##   pass args unmolested?
  ##
  my $method = "_user_".$cmd;
  if ( $self->can($method) ) {
    $self->core->log->debug("dispatching $method for ".$msg->{src_nick});
    $resp = $self->$method($context, $msg);
  }
  return $resp;
}



### Auth routines:

sub _do_login {
  ## backend handler for _cmd_login, returns constants
  ## $username should've already been normalized via lc_irc:
  my ($self, $context, $nick, $username, $passwd, $host) = @_;

  unless (exists $self->AccessList->{$context}->{$username}) {
    $self->core->log->debug("[$context] authfail; no such user: $username ($host)");
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
    $self->core->log->debug("[$context] authfail; no host match: $username ($host)");
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
    $self->core->log->debug("[$context] authfail; bad passwd: $username ($host)");
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

  $self->core->log->debug(
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


sub _user_add {
  my ($self, $context, $msg) = @_;
  my $core = $self->core;
  my $nick = $msg->{src_nick};
  my $auth_lev = $core->auth_level($context, $nick);
  my $auth_usr = $core->auth_username($context, $nick);
  
  unless ($auth_usr) {
    ## not logged in, return rpl
    $core->log->info("Failed user add attempt by $nick on $context");
    return rplprintf( $core->lang->{RPL_NO_ACCESS},
      { nick => $nick }
    );
  }

  my $pcfg = $core->get_plugin_cfg($self);
  
  my $required_base_lev = $pcfg->{RequiredPrivs}->{AddingUsers} // 2;
  
  unless ($auth_lev >= $required_base_lev) {
    ## doesn't match configured required base level
    ## otherwise this user can add users with lower access levs than theirs
    $core->log->info(
      "Failed user add; $nick ($auth_usr) has insufficient perms"
    );
    return rplprintf( $core->lang->{AUTH_NOT_ENOUGH_ACCESS},
      { nick => $nick, lev => $auth_lev }
    );
  }

  ## user add <username> <lev> <mask> <passwd> ?
  my @message = $msg->{message_array};
  my @args = @message[2 .. $#message];
  my ($target_usr, $target_lev, $mask, $passwd) = @args;
  unless ($target_usr && $target_lev && $mask && $passwd) {
    return "Usage: user add <username> <level> <mask> <initial_passwd>"
  }
  
  $target_usr = lc_irc($target_usr);
  
  unless ($target_lev =~ /^\d+$/) {
    return "Usage: user add <username> <level> <mask> <initial_passwd>"
  }
  
  if ( exists $self->AccessList->{$context}->{$target_usr} ) {
    $core->log->info(
      "Failed user add ($nick); $target_usr already exists on $context"
    );
    return rplprintf( $core->lang->{AUTH_USER_EXISTS},
      ## old/new username/user syntax:
      { nick => $nick, username => $target_usr, user => $target_usr }
    );
  }
  
  unless ($target_lev < $auth_lev) {
    ## user doesn't have enough access to add this level
    ## (superusers have to be hardcoded in auth.conf)
    $core->log->info(
      "Failed user add; lev ($target_lev) too high for $auth_usr ($nick)"
    );
    return rplprintf( $core->lang->{AUTH_NOT_ENOUGH_ACCESS},
      { nick => $nick, lev => $auth_lev }
    );
  }

  $passwd = $self->_mkpasswd($passwd);
  $mask   = normalize_mask($mask);
  
  ## add to AccessList
  $self->AccessList->{$context}->{$target_usr} = {
    Masks    => [ $mask ],
    Password => $passwd,  
    Level    => $target_lev,
    Flags    => {},
  };
  
  unless ( $self->_write_access_list ) {
    $core->log->warn("Couldn't _write_access_list in _user_add");
    $core->log->warn("AuthDB may be broken or inaccessible.");
    ## notify user also:
    $core->send_event( 'send_message',
      $context, $nick,
      "Failed access list write! Admin should check logs."
    );
  }

  return rplprintf( $core->lang->{AUTH_USER_ADDED},
    { 
      nick => $nick, 
      user => $target_usr, 
      username => $target_usr, 
      lev => $target_lev
    }
  );
}

sub _user_delete { _user_del(@_) }
sub _user_del {
  my ($self, $context, $msg) = @_;
  my $core = $self->core;
  my $nick = $msg->{src_nick};
  my $auth_lev = $core->auth_level($context, $nick);
  my $auth_usr = $core->auth_username($context, $nick);
  
  unless ($auth_usr) {
    $core->log->info("Failed user del attempt by $nick on $context");
    return rplprintf( $core->lang->{RPL_NO_ACCESS},
      { nick => $nick }
    );
  }

  my $pcfg = $core->get_plugin_cfg($self);
  
  my $required_base_lev = $pcfg->{RequiredPrivs}->{DeletingUsers} // 2;
  
  unless ($auth_lev >= $required_base_lev) {
    $core->log->info(
      "Failed user del; $nick ($auth_usr) has insufficient perms"
    );
    return rplprintf( $core->lang->{AUTH_NOT_ENOUGH_ACCESS},
      { nick => $nick, lev => $auth_lev }
    );
  }

  ## user del <username>
  my $target_usr = $msg->{message_array}[2];
  unless ($target_usr) {
    return "Usage: user del <username>"
  }
  
  $target_usr = lc_irc($target_usr);
  
  ## check if exists
  my $this_alist = $self->AccessList->{$context};
  unless (exists $this_alist->{$target_usr}) {
    return rplprintf( $core->lang->{AUTH_USER_NOSUCH},
      { nick => $nick, user => $target_usr, username => $target_usr }
    );
  }
  
  ## get target user's auth_level
  ## check if authed user has a higher identified level  
  my $target_lev = $this_alist->{$target_usr}->{Level};
  unless ($target_lev < $auth_lev) {
    $core->log->info(
      "Failed user del; $nick ($auth_usr) has insufficient perms"
    );
    return rplprintf( $core->lang->{AUTH_NOT_ENOUGH_ACCESS},
      { nick => $nick, lev => $auth_lev }
    );
  }

  ## delete users from AccessList
  delete $this_alist->{$target_usr};
  $core->log->info("User deleted: $target_usr ($target_lev) on $context");
  $core->log->info("Deletion issued by $nick ($auth_usr)");
  
  ## see if user is logged in, log them out if so
  my $auth_context = $core->State->{Auth}->{$context};
  for my $authnick (keys %$auth_context) {
    my $this_username = $auth_context->{Username};
    next unless $this_username eq $target_usr;
    $self->_do_logout($context, $authnick);
  }
  
  ## call a list sync
  unless ( $self->_write_access_list ) {
    $core->log->warn("Couldn't _write_access_list in _user_add");
    $core->log->warn("AuthDB may be broken or inaccessible.");
    ## notify user also:
    $core->send_event( 'send_message',
      $context, $nick,
      "Failed access list write! Admin should check logs."
    );
  }

  return rplprintf( $core->lang->{AUTH_USER_DELETED},
    { nick => $nick, user => $target_usr, username => $target_usr }
  );
}

sub _user_list {

}

sub _user_info {

}

sub _user_search {
  my ($self, $context, $msg) = @_;
  my $core = $self->core;
  my $nick = $msg->{src_nick};
  my $auth_lev = $core->auth_level($context, $nick);
  my $auth_usr = $core->auth_username($context, $nick);

}

sub _user_chflags {

}

sub _user_chmask {
  my ($self, $context, $msg) = @_;
  my $core = $self->core;
  my $nick = $msg->{src_nick};
  my $auth_lev = $core->auth_level($context, $nick);
  my $auth_usr = $core->auth_username($context, $nick);
  ## [+/-]mask syntax so as not to be confused with user del (much)
  ## FIXME normalize masks before adding ?
  ## call a list sync
}

sub _user_chpass {
  my ($self, $context, $msg) = @_;
  my $core = $self->core;
  my $nick = $msg->{src_nick};
  my $auth_lev = $core->auth_level($context, $nick);
  my $auth_usr = $core->auth_username($context, $nick);
  ## superuser (or configurable level.. ?) chpass ability
  ## return a formatted response to _cmd_user handler
}



### Utility methods:

sub _remove_if_lost {
  my ($self, $context, $nick) = @_;
  ## $self->_remove_if_lost( $context );
  ## $self->_remove_if_lost( $context, $nickname );
  ##
  ## called by event handlers that track users (or the bot) leaving
  ##
  ## if a nickname is specified, ask _check_for_shared if we still see
  ## this user, otherwise remove relevant Auth
  ##
  ## if no nickname is specified, do the above for all Auth'd users
  ## in the specified context
  ##
  ## return list of removed users

  ## no auth for specified context? then we don't care:
  return unless exists $self->core->State->{Auth}->{$context};

  my @removed;

  if ($nick) {
    ## ...does auth for this nickname in this context?
    return unless exists $self->core->State->{Auth}->{$context}->{$nick};

    unless ( $self->_check_for_shared($context, $nick) ) {
      ## we no longer share channels with this user
      ## if they're auth'd and their authorization is "ours", kill it
      ## call _do_logout to log them out and notify the pipeline
      ##
      ## _do_logout handles the messy details, incl. checking to make sure 
      ## that we are the "owner" of this auth:
      push(@removed, $nick) if $self->_do_logout($context, $nick);
    }

  } else {

    ## no nickname specified
    ## check trackable status all nicknames in State->{Auth}->{$context}
    for $nick (keys %{ $self->core->State->{Auth}->{$context} }) {
      unless ( $self->_check_for_shared($context, $nick) ) {
        push(@removed, $nick) if $self->_do_logout($context, $nick);
      }
    }

  }

  return @removed
}

sub _check_for_shared {
  ## $self->_check_for_shared( $context, $nickname );
  ##
  ## Query the IRC component to see if we share channels with a user.
  ## Actually just a simple frontend to get_irc_obj & PoCo::IRC::State
  ##
  ## Returns boolean true or false.
  ## Typically called after either the bot or a user leave a channel
  ## ( normally by _remove_if_lost() )
  ##
  ## Tells Auth whether or not we can sanely track this user.
  ## If we don't share channels it's difficult to get nick change
  ## notifications and generally validate authenticated users.
  my ($self, $context, $nick) = @_;
  my $irc = $self->core->get_irc_obj( $context );
  my @shared = $irc->nick_channels( $nick );
  return @shared ? 1 : 0 ;
}

sub _clear_context {
  my ($self, $context) = @_;
  ## $self->_clear_context( $context )
  ## Clear any State->{Auth} states for this pkg + context
  return unless $context;
  for my $nick (keys %{ $self->core->State->{Auth}->{$context} }) {
    $self->_do_logout($context, $nick);
  }
}

sub _clear_all {
  my ($self) = @_;
  ## $self->_clear_all()
  ## Clear any State->{Auth} states belonging to this pkg
  for my $context (keys %{ $self->core->State->{Auth} }) {
    for my $nick (keys %{ $self->core->State->{Auth}->{$context} }) {
      $self->core->log->debug("clearing: $nick [$context]");
      $self->_do_logout($context, $nick);
    }
  }
}

sub _do_logout {
  my ($self, $context, $nick) = @_;
  ## $self->_do_logout( $context, $nick )
  ## handles logout routines for 'lost' users
  ## normally called by method _remove_if_lost
  ##
  ## sends auth_user_logout event in addition to clearing auth hash
  ##
  ## returns the deleted user auth hash (or nothing)
  my $core = $self->core;
  my $auth_context = $core->State->{Auth}->{$context};

  if (exists $auth_context->{$nick}) {
    my $pkg = $auth_context->{$nick}->{Package};
    my $current_pkg = __PACKAGE__;
    if ($pkg eq $current_pkg) {
      my $host = $auth_context->{$nick}->{Host};
      my $username = $auth_context->{$nick}->{Username};
      my $level =  $auth_context->{$nick}->{Level};

      ## Bot_auth_user_logout ($context, $nick, $host, $username, $lev, $pkg):
      $self->core->send_event( 'auth_user_logout',
        $context,
        $nick,
        $host,
        $username,
        $level,
        $pkg,
      );

      $self->core->log->debug(
        "cleared auth state: $username ($nick on $context)"
      );

      return delete $auth_context->{$nick};
    } else {
      $self->core->log->debug(
        "skipped auth state, not ours: $nick [$context]"
      );
    }
  }
  return
}

sub _mkpasswd {
  my ($self, $passwd) = @_;
  return unless $passwd;
  ## $self->_mkpasswd( $passwd );
  ## simple frontend to Cobalt::Utils::mkpasswd()
  ## handles grabbing cfg opts for us:
  my $cfg = $self->core->get_plugin_cfg( $self );
  my $method = $cfg->{Method} // 'bcrypt';
  my $bcrypt_cost = $cfg->{Bcrypt_Cost} // '08';
  return mkpasswd($passwd, $method, $bcrypt_cost);
}



### Access list rw methods (serialize to YAML)
### These can also be used to read/write arbitrary authdbs

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

  my $serializer = Cobalt::Serializer->new( Logger => $core->log );
  my $accesslist = $serializer->readfile($authdb);
  return $accesslist
}

sub _write_access_list {
  my ($self, $authdb, $alist) = @_;
  $authdb = $self->DB_Path unless $authdb;
  $alist  = $self->AccessList unless $alist;
  my $core = $self->core;

  ## we don't want to write superusers back out
  ## copy from ref to a fresh hash to fuck with:
  my %hash = %$alist;
  for my $context (keys %hash) {
    for my $user (keys %{ $hash{$context} }) {
      if ( $hash{$context}->{$user}->{Flags}->{SUPERUSER} ) {
        delete $hash{$context}->{$user};
      }
    }
    ## don't need to write empty contexts either:
    delete $hash{$context} unless scalar keys %{ $hash{$context} };
  }

  ## don't need to write empty access lists to disk ...
  return unless scalar keys %hash;

  my $serializer = Cobalt::Serializer->new( Logger => $core->log );
  unless ( $serializer->writefile($authdb, \%hash) ) {
    $core->log->emerg("Failed to serialize db to disk: $authdb");
  }

  my $p_cfg = $core->get_plugin_cfg( $self );
  my $perms = $p_cfg->{Opts}->{AuthDB_Perms} // 0600;
  chmod($perms, $authdb);
}

no Moose; 1;
__END__


=pod

=head1 NAME

Cobalt::Plugin::Auth -- standard access control plugin

=head1 DESCRIPTION

This plugin provides the standard authorization and access control 
functionality for B<Cobalt>.

=head1 COMMANDS

=head2 Logging in

=head2 Changing your password

=head2 User administration

=head3 user add

=head3 user del

=head3 user chflags

=head3 user chpass




=head1 CONFIGURATION

=head2 plugins.conf

=head2 auth.conf


=head1 EMITTED EVENTS

=head2 Bot_auth_user_login

=head2 Bot_auth_failed_login

=head2 Bot_auth_user_logout



=head1 ACCEPTED EVENTS

Listens for the following events:

=over

=item *

Bot_connected

=item *

Bot_disconnected

=item *

Bot_private_msg

=item *

Bot_user_left

=item *

Bot_self_left

=item *

Bot_user_kicked

=item *

Bot_self_kicked

=item *

Bot_user_quit

=item *

Bot_nick_changed

=back


=head1 CAVEATS

This plugin generally assumes you only have one copy of it loaded.

It is perfectly possible to use either a replacement Auth system, or 
a supplementary Auth system, etc. Just don't try to load two copies of 
this particular plugin; there be dragons.


=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
