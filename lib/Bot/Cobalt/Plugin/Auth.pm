package Bot::Cobalt::Plugin::Auth;
our $VERSION = '0.200_48';

use 5.10.1;

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
## Auth hash should be adjusted when nicknames change.
## This plugin tracks 'lost' identified users and clears as needed
##
## Also see Bot::Cobalt::Core::ContextMeta::Auth

use Moo;

use Bot::Cobalt::Common;

use Bot::Cobalt::Serializer;

use Storable qw/dclone/;


### Constants, mostly for internal retvals:
use constant {
   ## _do_login RPL constants:
    SUCCESS   => 1,
    E_NOSUCH  => 2,
    E_BADPASS => 3,
    E_BADHOST => 4,
    E_NOCHANS => 5,
};


has 'core'    => ( is => 'rw', isa => Object, lazy => 1,
  default => sub {
    require Bot::Cobalt::Core; Bot::Cobalt::Core->instance;
  },
);


has 'DB_Path' => ( is => 'rw', isa => Str );

has 'AccessList' => ( is => 'rw', isa => HashRef,
  default => sub { {} },
);

has 'NON_RELOADABLE' => ( is => 'ro', default => sub { 1 } );


sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

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

  $core->log->info("Loaded");

  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistering core IRC plugin");
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
  my $context = ${$_[0]};
  $self->_clear_context($context);
  return PLUGIN_EAT_NONE
}

sub Bot_user_left {
  my ($self, $core) = splice @_, 0, 2;
  ## User left a channel
  ## If we don't share other channels, this user can't be tracked
  ## (therefore clear any auth entries for user belonging to us)
  my $left    = ${$_[0]};
  my $context = $left->context;

  my $channel = $left->channel;
  my $nick    = $left->src_nick;

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
  my $kick    = ${ $_[0] };
  my $context = $kick->context;
  my $nick    = $kick->src_nick;
  $self->_remove_if_lost($context, $nick);
  return PLUGIN_EAT_NONE
}

sub Bot_user_quit {
  my ($self, $core) = splice @_, 0, 2;
  my $quit    = ${$_[0]};
  my $context = $quit->context;
  my $nick    = $quit->src_nick;
  ## User quit, clear relevant auth entries
  ## We can call _do_logout directly here:
  $self->_do_logout($context, $nick);
  return PLUGIN_EAT_NONE
}

sub Bot_nick_changed {
  my ($self, $core) = splice @_, 0, 2;
  my $nchg = ${$_[0]};

  my $old = $nchg->old_nick;
  my $new = $nchg->new_nick;
  my $context = $nchg->context;

  ## a nickname changed, adjust Auth accordingly:
  $core->auth->move($context, $old, $new);

  return PLUGIN_EAT_NONE
}


sub Bot_private_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${$_[0]};
  my $context = $msg->context;

  my $command = $msg->message_array->[0] // return PLUGIN_EAT_NONE;
  $command = lc $command;

  ## simple method check/dispatch:
  my $resp;
  my $method = "_cmd_".$command;
  if ( $self->can($method) ) {
    $core->log->debug("dispatching '$command' for ".$msg->src_nick);
    $resp = $self->$method($context, $msg);
  }

  if (defined $resp) {
    my $target = $msg->src_nick;
    $core->log->debug("dispatching notice to $target");
    $core->send_event( 'notice', $context, $target, $resp );
  }

  return PLUGIN_EAT_NONE
}


### Frontends:

sub _cmd_login {
  ## interact with _do_login and set up response RPLs
  ## _do_login does the heavy lifting, we just talk to the user
  ## this is stupid, but I'm too lazy to fix
  my ($self, $context, $msg) = @_;
  my $l_user = $msg->message_array->[1] // undef;
  my $l_pass = $msg->message_array->[2] // undef;
  my $origin = $msg->src;
  my $nick = $msg->src_nick;

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
  ## SUCCESS E_NOSUCH E_BADPASS E_BADHOST E_NOCHANS
  my $retval = $self->_do_login($context, $nick, $l_user, $l_pass, $origin);
  my $rplvars = {
    context => $context,
    src => $origin,
    nick => $nick,
    user => $l_user,
  };
  my $resp;
  RETVAL: {
    if ($retval == SUCCESS) {
      ## add level to rplvars:
      $rplvars->{lev} = $self->core->auth->level($context, $nick);
      $resp = rplprintf( $self->core->lang->{AUTH_SUCCESS}, $rplvars );
      last RETVAL
    }
    if ($retval == E_NOSUCH) {
      $resp = rplprintf( $self->core->lang->{AUTH_FAIL_NO_SUCH}, $rplvars );
      last RETVAL
    }
    if ($retval == E_BADPASS) {
      $resp = rplprintf( $self->core->lang->{AUTH_FAIL_BADPASS}, $rplvars );
      last RETVAL
    }
    if ($retval == E_BADHOST) {
      $resp = rplprintf( $self->core->lang->{AUTH_FAIL_BADHOST}, $rplvars );
      last RETVAL
    }
    if ($retval == E_NOCHANS) {
      $resp = rplprintf( $self->core->lang->{AUTH_FAIL_NO_CHANS}, $rplvars );
      last RETVAL
    }
  }

  return $resp  ## return a response to the _private_msg handler
}

sub _cmd_chpass {
  my ($self, $context, $msg) = @_;
  ## 'self' chpass for logged-in users
  ##    chpass OLD NEW
  my $nick = $msg->src_nick;
  my $auth_for_nick = $self->core->auth->username($context, $nick);
  unless ($auth_for_nick) {
    return rplprintf( $self->core->lang->{RPL_NO_ACCESS},
      { nick => $nick },
    );
  }
  
  my $passwd_old = $msg->message_array->[1];
  my $passwd_new = $msg->message_array->[2];
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
        src => $msg->src,
      }
    );
  }
  
  my $new_hashed = $self->_mkpasswd($passwd_new);
  $user_rec->{Password} = $new_hashed;

  unless ( $self->_write_access_list ) {
    $self->core->log->warn(
      "Couldn't _write_access_list in _cmd_chpass",
    );
    $self->core->send_event( 'message',
      $context, $nick,
      "Failed access list write! Admin should check logs."
    );
  }

  return rplprintf( $self->core->lang->{AUTH_CHPASS_SUCCESS},
    {
      context => $context,
      nick => $nick,
      user => $auth_for_nick,
      src  => $msg->src,
    }
  );
}

sub _cmd_whoami {
  my ($self, $context, $msg) = @_;
  ## return current auth status
  my $nick = $msg->src_nick;
  my $auth_lev = $self->core->auth->level($context, $nick);
  my $auth_usr = $self->core->auth->username($context, $nick) 
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
  my $cmd = lc( $msg->message_array->[1] // '');

  my $resp;

  unless ($cmd) {
    return 'No command specified'
  }

  my $method = "_user_".$cmd;
  if ( $self->can($method) ) {
    $self->core->log->debug("dispatching $method for ".$msg->src_nick);
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
    $self->core->log->debug(
      "[$context] authfail; no such user: $username ($host)"
    );
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

  ## fail if we don't share channels with this user
  my $irc = $self->core->get_irc_obj($context);
  unless ($irc->nick_channels($nick)) {
    $self->core->log->debug(
      "[$context] authfail; no shared chans: $username ($host)"
    );
    $self->core->send_event( 'auth_failed_login',
      $context,
      $nick,
      $username,
      $host,
      'NO_SHARED_CHANS',
    );
    return E_NOCHANS
  }

  ## check username/passwd/host against AccessList:
  my $user_record = $self->AccessList->{$context}->{$username};
  ## masks should be normalized already:
  my @matched_masks;
  for my $mask (@{ $user_record->{Masks} }) {
    push(@matched_masks, $mask) if matches_mask($mask, $host);
  }

  unless (@matched_masks) {
    $self->core->log->info("[$context] authfail; no host match: $username ($host)");
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
    $self->core->log->info("[$context] authfail; bad passwd: $username ($host)");
    $self->core->send_event( 'auth_failed_login',
      $context,
      $nick,
      $username,
      $host,
      'BAD_PASS',
    );
    return E_BADPASS
  }

  my $level = $user_record->{Level};
  my %flags = %{ $user_record->{Flags} // {} };

  $self->core->auth->add(
    Context  => $context,
    Username => $username,
    Nickname => $nick,
    Host     => $host,
    Level    => $level,
    Flags    => \%flags,
    Alias    => $self->core->get_plugin_alias($self),
  );

  $self->core->log->info(
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
  my $nick = $msg->src_nick;
  my $auth_lev = $core->auth->level($context, $nick);
  my $auth_usr = $core->auth->username($context, $nick);
  
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
  my @message = @{ $msg->message_array };
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

  $core->log->info("New user added by $nick ($auth_usr)");
  $core->log->info("New user $target_usr ($mask) level $target_lev");
  
  unless ( $self->_write_access_list ) {
    $core->log->warn("Couldn't _write_access_list in _user_add");
    $core->send_event( 'message',
      $context, $nick,
      "Failed access list write! Admin should check logs."
    );
  }

  return rplprintf( $core->lang->{AUTH_USER_ADDED},
    { 
      nick => $nick, 
      user => $target_usr,
      username => $target_usr, 
      mask => $mask,
      lev => $target_lev
    }
  );
}

sub _user_delete { _user_del(@_) }
sub _user_del {
  my ($self, $context, $msg) = @_;
  my $core = $self->core;
  my $nick = $msg->src_nick;
  my $auth_lev = $core->auth->level($context, $nick);
  my $auth_usr = $core->auth->username($context, $nick);
  
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
  my $target_usr = $msg->message_array->[2];
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
  my $auth_context = $core->auth->list($context);
  for my $authnick (keys %$auth_context) {
    my $this_username = $auth_context->{$authnick}->{Username};
    next unless $this_username eq $target_usr;
    $self->_do_logout($context, $authnick);
  }
  
  ## call a list sync
  unless ( $self->_write_access_list ) {
    $core->log->warn("Couldn't _write_access_list in _user_add");
    $core->send_event( 'message',
      $context, $nick,
      "Failed access list write! Admin should check logs."
    );
  }

  return rplprintf( $core->lang->{AUTH_USER_DELETED},
    { nick => $nick, user => $target_usr, username => $target_usr }
  );
}

sub _user_list {
  my ($self, $context, $msg) = @_;
  my $core = $self->core;
  my $nick = $msg->src_nick;
  my $auth_lev = $core->auth->level($context, $nick);
  my $auth_usr = $core->auth->username($context, $nick);
  
  return rplprintf( $core->lang->{RPL_NO_ACCESS}, { nick => $nick } )
    unless $auth_lev;
  
  my $alist = $self->AccessList->{$context} // {};
  
  my $respstr = "Users ($context): ";
  USER: for my $username (keys %$alist) {
    my $lev = $alist->{$username}->{Level};
    $respstr .= "$username ($lev)   ";
    
    if ( length($respstr) > 250 ) {
      $core->send_event( 'message',
        $context,
        $nick,
        $respstr
      );
      $respstr = '';
    }
    
  } ## USER
  return $respstr if $respstr;
}

sub _user_whois {
  my ($self, $context, $msg) = @_;
  my $core = $self->core;
  my $nick = $msg->src_nick;
  my $auth_lev = $core->auth->level($context, $nick);
  my $auth_usr = $core->auth->username($context, $nick);

  return rplprintf( $core->lang->{RPL_NO_ACCESS}, { nick => $nick } )
    unless $auth_lev;

  my $target_nick = $msg->message_array->[2];
  
  if ( my $target_lev = $core->auth->level($context, $target_nick) ) {
    my $target_usr = $core->auth->username($context, $target_nick);
    return "$target_nick is user $target_usr with level $target_lev"
  } else {
    return "$target_nick is not currently logged in"
  }
}

sub _user_info {
  my ($self, $context, $msg) = @_;
  my $core = $self->core;
  my $nick = $msg->src_nick;
  my $auth_lev = $core->auth->level($context, $nick);
  my $auth_usr = $core->auth->username($context, $nick);
  
  unless ($auth_lev) {
    return rplprintf( $core->lang->{RPL_NO_ACCESS}, { nick => $nick } );
  }
  
  my $target_usr = $msg->message_array->[2];
  unless ($target_usr) {
    return 'Usage: user info <username>'
  }
  
  $target_usr = lc_irc($target_usr);
  
  my $alist_context = $self->AccessList->{$context};
  
  unless (exists $alist_context->{$target_usr}) {
    return rplprintf( $core->lang->{AUTH_USER_NOSUCH},
      { nick => $nick, user => $target_usr, username => $target_usr }
    );
  }

  my $usr = $alist_context->{$target_usr};
  my $usr_lev = $usr->{Level};

  my $usr_maskref = $usr->{Masks};
  my @masks = @$usr_maskref;
  my $maskcount = @masks;
  $core->send_event( 'message', $context, $nick,
    "User $target_usr is level $usr_lev, $maskcount masks listed"
  );
  
  my @flags = keys %{ $usr->{Flags} };
  my $flag_repl = "Flags: ";
  while (my $this_flag = shift @flags) {
    $flag_repl .= $this_flag;
    if (length $flag_repl > 300 || !@flags) {
      $core->send_event('message', $context, $nick, $flag_repl);
      $flag_repl = '';
    }
  }

  my $mask_repl = "Masks: ";
  while (my $this_mask = shift @masks) {
    $mask_repl .= $this_mask;
    if (length $mask_repl > 300 || !@masks) {
      $core->send_event('message', $context, $nick, $mask_repl);
      $mask_repl = '';
    }
  }

  return    
}

sub _user_search {
  my ($self, $context, $msg) = @_;
  my $core = $self->core;
  my $nick = $msg->src_nick;
  my $auth_lev = $core->auth->level($context, $nick);
  my $auth_usr = $core->auth->username($context, $nick);

  ## search by: username, host, ... ?
  ## limit results ?

}

sub _user_chflags {

}

sub _user_chmask {
  my ($self, $context, $msg) = @_;
  my $core = $self->core;
  my $nick = $msg->src_nick;
  my $auth_lev = $core->auth->level($context, $nick);
  my $auth_usr = $core->auth->username($context, $nick);
  
  my $pcfg = $core->get_plugin_cfg($self);
  ## If you can't delete users, you probably shouldn't be permitted 
  ## to delete their masks, either
  my $req_lev = $pcfg->{RequiredPrivs}->{DeletingUsers};
  
  ## You also should have higher access than your target
  ## (unless you're a superuser)
  my $target_user    = $msg->message_array->[2];
  my $mask_specified = $msg->message_array->[3];
  
  unless ($target_user && $mask_specified) {
    return "Usage: user chmask <user> [+/-]<mask>"
  }

  my $alist_ref;  
  unless ( $alist_ref = $self->AccessList->{$context}->{$target_user}) {
    return rplprintf( $core->lang->{AUTH_USER_NOSUCH},
      { nick => $nick, user => $target_user, username => $target_user }
    );
  }
  
  my $target_user_lev = $alist_ref->{Level};
  my $flags = $core->auth->flags($context, $nick);
  
  unless ($auth_lev >= $req_lev 
    && ($auth_lev > $target_user_lev || $flags->{SUPERUSER}) ) {
    
    my $src = $msg->src;
    $core->log->warn(
      "Access denied in chmask: $src tried to chmask $target_user"
    );
    
    return rplprintf( $core->lang->{AUTH_NOT_ENOUGH_ACCESS},
      { nick => $nick, lev => $auth_lev }
    );
  }
  
  my ($oper, $host) = $mask_specified =~ /^(\+|\-)(\S+)/;
  unless ($oper && $host) {
    return "Bad mask specification, should be operator (+ or -) followed by mask"
  }

  if ($oper eq '+') {
    ## Add a mask
  } else {
    ## Remove a mask
  }
  
  ## [+/-]mask syntax
  ## FIXME normalize masks before adding 
  ## call a list sync
}

sub _user_chpass {
  my ($self, $context, $msg) = @_;
  my $core = $self->core;
  my $nick = $msg->src_nick;
  my $auth_lev = $core->auth->level($context, $nick);
  my $auth_usr = $core->auth->username($context, $nick);
  
  unless ($core->auth->has_flag($context, $nick, 'SUPERUSER')) {
    return "Must be flagged SUPERUSER to use user chpass"
  }
  
  my $target_user = $msg->message_array->[2];
  my $new_passwd  = $msg->message_array->[3];
  
  unless ($target_user && $new_passwd) {
    return "Usage: user chpass <username> <new_passwd>"
  }
  
  my $this_alist = $self->AccessList->{$context};
  unless ($this_alist->{$target_user}) {
    return rplprintf( $core->lang->{AUTH_USER_NOSUCH},
      { nick => $nick, user => $target_user, username => $target_user },
    );
  }
  
  my $hashed = $self->_mkpasswd($new_passwd);
  
  $core->log->info(
    "$nick ($auth_usr) CHPASS for $target_user"
  );
  
  $this_alist->{$target_user}->{Password} = $hashed;
  
  if ( $self->_write_access_list ) {
    return rplprintf( $core->lang->{AUTH_CHPASS_SUCCESS},
      { nick => $nick, user => $target_user, username => $target_user },
    );
  } else {
    $self->core->log->warn(
      "Couldn't _write_access_list in _cmd_chpass",
    );
    
    return "Failed access list write! Admin should check logs."
  }
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
  my $authref;
  return unless $authref = $self->core->auth->list($context);

  my @removed;

  if ($nick) {
    ## ...does auth for this nickname in this context?
    return unless exists $authref->{$nick};

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
    ## check trackable status for all known
    for $nick (keys %$authref) {
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
  return unless $context;
  for my $nick ( $self->core->auth->list($context) ) {
    $self->_do_logout($context, $nick);
  }
}

sub _clear_all {
  my ($self) = @_;
  ## $self->_clear_all()
  ## clear any states belonging to us
  for my $context ( $self->core->auth->list() ) {

    NICK: for my $nick ( $self->core->auth->list($context) ) {

      next NICK unless $self->core->auth->alias($context, $nick)
                    eq $self->core->get_plugin_alias($self);

      $self->core->log->debug("clearing: $nick [$context]");
      $self->_do_logout($context, $nick);
    } ## NICK
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
  my $auth_context = $core->auth->list($context);

  if (exists $auth_context->{$nick}) {
    my $pkg = $core->auth->alias($context, $nick);
    my $current_pkg = $core->get_plugin_alias($self);
    if ($pkg eq $current_pkg) {
      my $host     = $core->auth->host($context, $nick);
      my $username = $core->auth->username($context, $nick);
      my $level    = $core->auth->level($context, $nick);

      ## Bot_auth_user_logout ($context, $nick, $host, $username, $lev, $pkg):
      $core->send_event( 'auth_user_logout',
        $context,
        $nick,
        $host,
        $username,
        $level,
        $pkg,
      );

      $core->log->debug(
        "cleared auth state: $username ($nick on $context)"
      );

      return $core->auth->del($context, $nick);
      
    } else {
      $core->log->debug(
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
  ## simple frontend to Bot::Cobalt::Utils::mkpasswd()
  ## handles grabbing cfg opts for us:
  my $cfg = $self->core->get_plugin_cfg( $self );
  my $method = $cfg->{Method} // 'bcrypt';
  my $bcrypt_cost = $cfg->{Bcrypt_Cost} || '08';
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

  my $serializer = Bot::Cobalt::Serializer->new( Logger => $core->log );
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
  my $cloned_alist = dclone($alist);
  my %hash = %$cloned_alist;
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

  my $serializer = Bot::Cobalt::Serializer->new( Logger => $core->log );
  unless ( $serializer->writefile($authdb, \%hash) ) {
    $core->log->emerg("Failed to serialize db to disk: $authdb");
  }

  my $p_cfg = $core->get_plugin_cfg( $self );
  my $perms = oct( $p_cfg->{Opts}->{AuthDB_Perms} // '0600' );
  chmod($perms, $authdb);
}

no Moo; 1;
__END__


=pod

=head1 NAME

Bot::Cobalt::Plugin::Auth -- standard access control plugin

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

=head3 user chmask

=head3 user whoami

=head3 user whois

=head3 user info

=head3 user list

=head3 user search



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
