package Bot::Cobalt::Plugin::RDB;
our $VERSION = '0.005';

## 'Random' DBs, often used for quotebots or random chatter

use strictures 1;
use 5.12.0;

use Bot::Cobalt;
use Bot::Cobalt::Common;
use Bot::Cobalt::Plugin::RDB::Database;

use POE;

use File::Spec;

use List::Util   qw/shuffle/;

## Some de-Moo'd accessors for easy plugin reloads:

sub new { bless {}, shift }

sub DBmgr {
  my ($self) = @_;
  
  unless ($self->{DBMGR}) {
    my $cfg = core->get_plugin_cfg($self);
    my $cachekeys = $cfg->{Opts}->{CacheItems} // 30;

    my $rdbdir = File::Spec->catdir(
      core()->var,
      $cfg->{Opts}->{RDBDir} ? $cfg->{Opts}->{RDBDir} : ('db', 'rdb')
    );

    $self->{DBMGR} = Bot::Cobalt::Plugin::RDB::Database->new(
      CacheKeys => $cachekeys,
      RDBDir    => $rdbdir,
    );
  }
  
  $self->{DBMGR}
}

sub rand_delay {
  my ($self, $delay) = @_;
  return $self->{RANDDELAY} = $delay if defined $delay;
  $self->{RANDDELAY}
}

sub SessionID {
  my ($self, $id) = @_;
  return $self->{SESSID} = $id if defined $id;
  $self->{SESSID}
}

sub AsyncSessionID {
  my ($self, $id) = @_;
  return $self->{ASYNCID} = $id if defined $id;
  $self->{ASYNCID}
}

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  register($self, 'SERVER',
    [ 
      'public_msg',
      'rdb_broadcast',
      'rdb_triggered',
    ],
  );
  
  ## if the rdbdir doesn't exist, ::Database will try to create it
  ## (it'll also handle creating 'main' for us)
  ## DBmgr must be called after core() is set:
  my $dbmgr = $self->DBmgr;

  my $keys_c = $dbmgr->get_keys('main');
  core->Provided->{randstuff_items} = $keys_c;

  ## kickstart a randstuff timer (named timer for rdb_broadcast)
  ## delay is in Opts->RandDelay as a timestr
  ## (0 turns off timer)
  my $cfg = core->get_plugin_cfg( $self );
  my $randdelay = $cfg->{Opts}->{RandDelay} // '30m';
  logger->debug("randdelay: $randdelay");

  $randdelay = timestr_to_secs($randdelay) unless $randdelay =~ /^\d+$/;

  $self->rand_delay( $randdelay );

  if ($randdelay) {
    core->timer_set( $randdelay, 
      { 
        Event => 'rdb_broadcast', 
        Alias => core->get_plugin_alias($self) 
      }, 
      'RANDSTUFF'
    );
  }

  if ($cfg->{Opts}->{AsyncSearch}) {
    POE::Session->create(
      object_states => [
        $self => [
          '_start',
          
          'poe_post_search',
          
          'poe_got_result',
          
          'poe_got_error',
        ],
      ],
    );
  }

  logger->info("Registered, $keys_c items in main RDB");

  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;

  core->log->info("Unregistering random stuff");

  $poe_kernel->alias_remove('sess_'. core->get_plugin_alias($self) );

  if ( $self->AsyncSessionID ) {
    $poe_kernel->post( $self->AsyncSessionID, 'shutdown' );
  }

  delete core->Provided->{randstuff_items};

  return PLUGIN_EAT_NONE
}


sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${$_[0]};
  my $context = $msg->context;

  my @handled = qw/
    randstuff
    randq
    rdb    
  /;

  ## would be better in a public_cmd_, but eh, darkbot legacy syntax..
  return PLUGIN_EAT_NONE unless $msg->highlight;
  ## uses message_array_sp, ie spaces are preserved
  ## (so don't include them prior to rdb names, for example)
  my $msg_arr = $msg->message_array_sp;
  ## since this is a highlighted message, bot's nickname is first
  my ($cmd, @message) = @$msg_arr[1 .. (scalar @$msg_arr - 1)];
  $cmd = lc($cmd||'');
  ## ..if it's not @handled we don't care:
  return PLUGIN_EAT_NONE unless $cmd and $cmd ~~ @handled;

  core->log->debug("Dispatching $cmd");

  ## dispatcher:
  my ($id, $resp);

  CMD: {
    if ($cmd eq "randstuff") {
      $resp = $self->_cmd_randstuff(\@message, $msg);
      last CMD
    }
    
    if ($cmd eq "randq") {
      $resp = $self->_cmd_randq(\@message, $msg, 'randq');
      last CMD
    }
    
    if ($cmd eq "rdb") {
      $resp = $self->_cmd_rdb(\@message, $msg);
      last CMD
    }
  }

#  $resp = "No output for $cmd - BUG!" unless $resp;

  my $channel = $msg->channel;
  core->log->debug("dispatching msg -> $channel");
  broadcast( 'message', $context, $channel, $resp );

  return PLUGIN_EAT_NONE
}


  ### command handlers ###

sub _cmd_randstuff {
  ## $parsed_msg_a  == message_array without prefix/cmd
  ## $msg == original message obj
  my ($self, $parsed_msg_a, $msg) = @_;
  my @message = @{ $parsed_msg_a };
  my $src_nick = $msg->src_nick;
  my $context  = $msg->context;

  my $pcfg = core->get_plugin_cfg( $self );
  my $required_level = $pcfg->{RequiredLevels}->{rdb_add_item} // 1;

  my $rplvars;
  $rplvars->{nick} = $src_nick;

  unless ( core->auth->level($context, $src_nick) >= $required_level ) {
    return rplprintf( core->lang->{RPL_NO_ACCESS}, $rplvars );
  }
  
  my $rdb = 'main';      # randstuff is 'main', darkbot legacy
  $rplvars->{rdb} = $rdb;
  ## ...but this may be randstuff ~rdb ... syntax:
  if (@message && index($message[0], '~') == 0) {
    $rdb = substr(shift @message, 1);
    $rplvars->{rdb} = $rdb;
    my $dbmgr = $self->DBmgr;
    unless ($rdb && $dbmgr->dbexists($rdb) ) {
      ## ~rdb specified but nonexistant
      return rplprintf( core->lang->{RDB_ERR_NO_SUCH_RDB}, $rplvars );
    }
  }

  ## should have just the randstuff itself now (and maybe a different rdb):
  my $randstuff_str = join ' ', @message;
  $randstuff_str = decode_irc($randstuff_str);

  unless ($randstuff_str) {
    return rplprintf( core->lang->{RDB_ERR_NO_STRING}, $rplvars );
  }

  ## call _add_item
  my $username = core->auth->username($context, $src_nick);
  my ($newidx, $err) =
    $self->_add_item($rdb, $randstuff_str, $username);
  $rplvars->{index} = $newidx;
  ## _add_item returns either a status from ::Database->put
  ## or a new item key:

  unless ($newidx) {

    if ($err eq "RDB_DBFAIL") {
      return rplprintf( core->lang->{RPL_DB_ERR}, $rplvars )
    } elsif ($err eq "RDB_NOSUCH") {
      return rplprintf( core->lang->{RDB_ERR_NO_SUCH_RDB}, $rplvars )
    } else {
      return "Unknown error status: $err"
    }

  } else {
    return rplprintf( core->lang->{RDB_ITEM_ADDED}, $rplvars );
  }
  
}

sub _select_random {
  my ($self, $msg, $rdb, $quietfail) = @_;
  my $dbmgr  = $self->DBmgr;
  my $retval = $dbmgr->random($rdb);
  ## we'll get either an item as hashref or err status:
  
  if ($retval && ref $retval) {
    my $content = ref $retval eq 'HASH' ?
                  $retval->{String}
                  : $retval->[0] ;
    if ($self->{LastRandom}
        && $self->{LastRandom} eq $content
    ) {
      $retval  = $dbmgr->random($rdb);
      if      (ref $retval eq 'HASH') {
        $content = $retval->{String}//''
      } elsif (ref $retval eq 'ARRAY') {
        $content = $retval->[0]//''
      }
    }
    $self->{LastRandom} = $content;
    return $content
  } else {
    ## do nothing if we're supposed to fail quietly
    ## (e.g. in a rdb_triggered for an empty rdb)
    return if $quietfail;
    my $rpl;
    given ($dbmgr->Error) {
      $rpl = "RDB_ERR_NO_SUCH_RDB" when "RDB_NOSUCH";
      $rpl = "RPL_DB_ERR"          when "RDB_DBFAIL";
      ## send nothing if this rdb has no keys:
      return                       when "RDB_NOSUCH_ITEM";
      ## unknown error status?
      default { $rpl = "RPL_DB_ERR" }
    }
    return rplprintf( core->lang->{$rpl},
      {
        nick => $msg->src_nick//'',
        rdb  => $rdb,
      },
    );
  }
}


sub _cmd_randq {
  my ($self, $parsed_msg_a, $msg, $type, $rdbpassed, $strpassed) = @_;
  my @message = @{ $parsed_msg_a };

  ## also handler for 'rdb search rdb str'
  my $dbmgr = $self->DBmgr;

  my($str, $rdb);
  if    ($type eq 'random') {
    ## this is actually deprecated
    ## use '~main' rdb info3 topic trick instead
    return $self->_select_random($msg, 'main');
  } elsif ($type eq 'rdb') {
    $rdb = $rdbpassed;
    $str = $strpassed;
  } else {    ## 'randq'
    $rdb = 'main';
    ## search what looks like irc quotes by default:
    $str = shift @message // '<*>';
  }


  core->log->debug("dispatching search for $str in $rdb");

  if ( $self->SessionID ) {
    ## if we have asyncsearch, return immediately
    
    unless ( $dbmgr->dbexists($rdb) ) {
      return rplprintf( core()->lang->{RDB_ERR_NO_SUCH_RDB},
        { nick => $msg->src_nick, rdb => $rdb },
      );
    }
    
    $poe_kernel->post( $self->SessionID,
      'poe_post_search',
      $rdb,
      $str,
      {          ## Hints hash
        Glob     => $str,
        Context  => $msg->context,
        Channel  => $msg->channel,
        Nickname => $msg->src_nick,
        GetType  => 'string',
        RDB      => $rdb,
      },
    );
    
    return
  }
  
  my $match = $dbmgr->search($rdb, $str, 'WANTONE');

  if (!$match && $dbmgr->Error) {
    core->log->debug("Error status from search(): $dbmgr->Error");
    my $rpl;
    given ($dbmgr->Error) {
      $rpl = "RPL_DB_ERR"          when "RDB_DBFAIL";
      $rpl = "RDB_ERR_NO_SUCH_RDB" when "RDB_NOSUCH";
      ## not an arrayref and not a known error status, wtf?
      default { $rpl = "RPL_DB_ERR" }
    }
    return rplprintf( core->lang->{$rpl},
      { nick => $msg->src_nick, rdb => $rdb }
    );
  }

  return 'No match' if not defined $match;
  
  core->log->debug("dispatching get() for $match in $rdb");

  my $item = $dbmgr->get($rdb, $match);
  unless ($item && ref $item) {
    core->log->debug("Error status from get(): $item");
    my $rpl;
    given ($dbmgr->Error) {
      $rpl = "RDB_ERR_NO_SUCH_ITEM" when "RDB_NOSUCH_ITEM";
      ## an unknown non-hashref $item is also a DB_ERR:
      default { "RPL_DB_ERR" }
    }
    return rplprintf( core->lang->{$rpl},
      { 
        nick  => $msg->src_nick//'',
        rdb   => $rdb, 
        index => $match 
      }
    );
  }

  my $content = ref $item eq 'HASH' ?
                $item->{String}
                : $item->[0] ;
  $content = '(undef - broken db!)' unless defined $content;
  
  return "[$match] $content" ;
}


sub _cmd_rdb {
  ## Command dispatcher for:
  ##   rdb add
  ##   rdb del
  ##   rdb get 
  ##   rdb dbadd
  ##   rdb dbdel
  ##   rdb info
  ##   rdb search
  ##   rdb searchidx
  ## FIXME rdb dblist ?
  my ($self, $parsed_msg_a, $msg) = @_;
  my @message = @{ $parsed_msg_a };

  my $pcfg = core->get_plugin_cfg( $self );
  my $required_levs = $pcfg->{RequiredLevels} // {};
  ## this hash maps commands to levels.
  ## commands not found here aren't recognized.
  my %access_levs = (
    ## FIXME document these ...
    count  => $required_levs->{rdb_count}     // 0,
    get    => $required_levs->{rdb_get_item}  // 0,
    dblist => $required_levs->{rdb_dblist}    // 0,
    info   => $required_levs->{rdb_info}      // 0,
    dbadd  => $required_levs->{rdb_create}    // 9999,
    dbdel  => $required_levs->{rdb_delete}    // 9999,
    add    => $required_levs->{rdb_add_item}  // 2,
    del    => $required_levs->{rdb_del_item}  // 3,
    search    => $required_levs->{rdb_search} // 0,
    searchidx => $required_levs->{rdb_search} // 0,
  );

  my $cmd = lc(shift @message || '');
  $cmd = 'del' if $cmd eq 'delete';

  my @handled = keys %access_levs;
  unless ($cmd && $cmd ~~ @handled) {
    return "Commands: add <rdb> <item> ; del <rdb> <idx>, info <rdb> <idx> ; "
           ."get <rdb> <idx> ; search(idx) <rdb> <str> ; count <rdb> <str> ; "
           ."dbadd <rdb> ; dbdel <rdb>";
  }
    
  my $context  = $msg->context;
  my $nickname = $msg->src_nick;

  my $user_lev = core->auth->level($context, $nickname) // 0;
  unless ($user_lev >= $access_levs{$cmd}) {
    return rplprintf( core->lang->{RPL_NO_ACCESS},
      { nick => $nickname }
    );
  }

  my $method = '_cmd_rdb_'.$cmd;
  return $self->$method($msg, \@message) if $self->can($method);
  
  return "No handler found for command $cmd"
}

sub _cmd_rdb_dbadd {
  my ($self, $msg, $parsed_args) = @_;
  
  my $dbmgr = $self->DBmgr;
  
  my ($rdb) = @$parsed_args;
  
  return 'Syntax: rdb dbadd <RDB>' unless $rdb;

  return 'RDB name must be in the a-z0-9 set'
    unless $rdb =~ /^[a-z0-9]+$/;

  return 'RDB name must be less than 32 characters'
    unless length $rdb <= 32;

  my $retval = $dbmgr->createdb($rdb);

  my $rplvars = {
    nick => $msg->src_nick,
    rdb  => $rdb,
    op   => 'dbadd',
  };
  
  my $rpl;      
  if ($retval) {
    $rpl = "RDB_CREATED";
  } else {
    given ($dbmgr->Error) {
      $rpl = "RDB_ERR_RDB_EXISTS" when "RDB_EXISTS";
      $rpl = "RDB_DBFAIL"         when "RDB_DBFAIL";        
      default { return "Unknown retval $retval from createdb"; }
    }
  }
  
  return rplprintf( core->lang->{$rpl}, $rplvars );
}

sub _cmd_rdb_dbdel {
  my ($self, $msg, $parsed_args) = @_;
  
  my $dbmgr = $self->DBmgr;
  
  my ($rdb) = @$parsed_args;

  return 'Syntax: rdb dbdel <RDB>' unless $rdb;
  
  my $rplvars = {
    nick => $msg->src_nick,
    rdb  => $rdb,
    op   => 'dbdel',
  };

  my ($retval, $err) = $self->_delete_rdb($rdb);
  
  my $rpl;
  if ($retval) {
    $rpl = "RDB_DELETED";
  } else {
    given ($err) {
      $rpl = "RDB_ERR_NOTPERMITTED" when "RDB_NOTPERMITTED";
      $rpl = "RDB_ERR_NO_SUCH_RDB"  when "RDB_NOSUCH";
      $rpl = "RPL_DB_ERR"           when "RDB_DBFAIL";
      $rpl = "RDB_UNLINK_FAILED"    when "RDB_FILEFAILURE";
      default { return "Unknown err $err from _delete_rdb" }
    }
  }
  
  return rplprintf( core->lang->{$rpl}, $rplvars );
}

sub _cmd_rdb_add {
  my ($self, $msg, $parsed_args) = @_;
  
  my ($rdb, @pieces) = @$parsed_args;
  my $item = join ' ', @pieces;

  return 'Syntax: rdb add <RDB> <item>' unless $rdb and $item;

  my $rplvars = {
    nick => $msg->src_nick,
    rdb  => $rdb,
  };
  
  my $username = core->auth->username($msg->context, $msg->src_nick);

  my ($retval, $err) = 
    $self->_add_item($rdb, decode_irc($item), $username);

  my $rpl;
  if ($retval) {
    $rplvars->{index} = $retval;
    $rpl = "RDB_ITEM_ADDED";
  } else {
    given ($err) {
      $rpl = "RDB_ERR_NO_SUCH_RDB" when "RDB_NOSUCH";
      $rpl = "RPL_DB_ERR"          when "RDB_DBFAIL";
      default { return "Unknown err $err from _add_item" }
    }
  }

  return rplprintf( core->lang->{$rpl}, $rplvars )
}

sub _cmd_rdb_del {
  my ($self, $msg, $parsed_args) = @_;
  
  my ($rdb, $item_idx) = @$parsed_args;

  return 'Syntax: rdb del <RDB> <index number>'
    unless $rdb and $item_idx;

  my $rplvars = {
    nick => $msg->src_nick,
    rdb  => $rdb,
    index => $item_idx,
  };
  
  my $username = core->auth->username($msg->context, $msg->src_nick);

  my ($retval, $err) = 
    $self->_delete_item($rdb, $item_idx, $username);

  my $rpl;
  if ($retval) {
    $rpl = "RDB_ITEM_DELETED";
  } else {
    given ($err) {
      $rpl = "RDB_ERR_NO_SUCH_RDB"  when "RDB_NOSUCH";
      $rpl = "RPL_DB_ERR"           when "RDB_DBFAIL";
      $rpl = "RDB_ERR_NO_SUCH_ITEM" when "RDB_NOSUCH_ITEM";
    }
  }

  return rplprintf( core->lang->{$rpl}, $rplvars )
}

sub _cmd_rdb_get {
  my ($self, $msg, $parsed_args) = @_;
  
  my $dbmgr = $self->DBmgr;

  my ($rdb, $idx) = @$parsed_args;

  return 'Syntax: rdb get <RDB> <index key>'
    unless $rdb and $idx;

  return "Invalid item index ID"
    unless $idx =~ /^[0-9a-f]+$/i;

  $idx = lc($idx);

  my $rplvars = {
    nick => $msg->src_nick,
    rdb  => $rdb,
    ## Cut the index ID in response string to 16 chars
    ## Gives some flex without making flooding too easy
    index => substr($idx, 0, 16),
  };
  
  unless ( $dbmgr->dbexists($rdb) ) {
    return rplprintf( core->lang->{RDB_ERR_NO_SUCH_RDB}, $rplvars );
  }
  
  my $item = $dbmgr->get($rdb, $idx);

  my $resp;
  if ($item && ref $item) {
    my $content = ref $item eq 'HASH' ?
                  $item->{String}
                  : $item->[0] ;
    $content = '(undef - broken db?)' unless defined $content;

    $resp = "[$idx] $content"
  } else {
    my $err = $dbmgr->Error || 'Unknown error';
    my $rpl;
    given ($err) {
      $rpl = "RDB_ERR_NO_SUCH_ITEM"  when "RDB_NOSUCH_ITEM";
      $rpl = "RDB_ERR_NO_SUCH_RDB"   when "RDB_NOSUCH";
      $rpl = "RPL_DB_ERR"            when "RDB_DBFAIL";
      default { return "Error: $err" }
    }

    $resp = rplprintf( core->lang->{$rpl}, $rplvars );
  }
  
  return $resp
}

sub _cmd_rdb_info {
  my ($self, $msg, $parsed_args) = @_;
  
  my $dbmgr = $self->DBmgr;

  my ($rdb, $idx) = @$parsed_args;

  return 'Syntax: rdb info <RDB> <index key>'
    unless $rdb;
  
  my $rplvars = {
    nick => $msg->src_nick,
    rdb  => $rdb,
  };

  return rplprintf( core->lang->{RDB_ERR_NO_SUCH_RDB}, $rplvars )
    unless $dbmgr->dbexists($rdb);

  if (!$idx) {
    my $n_keys = $dbmgr->get_keys($rdb);
    return "RDB $rdb has $n_keys items"
  } else {
    return "Invalid item index ID"
      unless $idx =~ /^[0-9a-f]+$/i;
    $idx = lc($idx);
  }
  
  $rplvars->{index} = substr($idx, 0, 16);

  my $item = $dbmgr->get($rdb, $idx);

  unless ($item && ref $item) {
    my $err = $dbmgr->Error || 'Unknown error';
    my $rpl;
    given ($err) {
      $rpl = "RDB_ERR_NO_SUCH_ITEM" when "RDB_NOSUCH_ITEM";
      $rpl = "RDB_ERR_NO_SUCH_RDB"  when "RDB_NOSUCH";
      $rpl = "RPL_DB_ERR"           when "RDB_DBFAIL";
      default { return "Error: $err" }
    }
    return rplprintf( core->lang->{$rpl}, $rplvars );
  }

  my $addedat_ts = ref $item eq 'HASH' ?
                   $item->{AddedAt}
                   : $item->[1];

  my $added_by   = ref $item eq 'HASH' ?
                   $item->{AddedBy}
                   : $item->[2];

  my $added_dt = DateTime->from_epoch(
    epoch => $addedat_ts // 0
  );

  $rplvars->{date} = $added_dt->date;
  $rplvars->{time} = $added_dt->time;
  $rplvars->{addedby} = $added_by // '(undef)' ;  

  return rplprintf( core->lang->{RDB_ITEM_INFO}, $rplvars );
}

sub _cmd_rdb_count {
  my ($self, $msg, $parsed_args) = @_;
  
  my ($rdb, $str) = @$parsed_args;

  ## count <RDB> is the same as info <RDB>
  return $self->_cmd_rdb_info($msg, $parsed_args)
    unless defined $str;

  return 'Syntax: rdb count <RDB> <str>'
    unless defined $rdb;

  my $indices = $self->_searchidx($msg, 'count', $rdb, $str);
  
  ## Same deal as searchidx, return immediately if this is async.
  return unless ref $indices eq 'ARRAY';

  my $count = @$indices;
  return $msg->src_nick .": Found $count matches";
}

sub _cmd_rdb_search {
  my ($self, $msg, $parsed_args) = @_;
  
  ## Pass-thru to _cmd_randq

  my ($rdb, $str) = @$parsed_args;
  
  $str = '*' unless $str;
  return 'Syntax: rdb search <RDB> <string>' unless $rdb;

  return $self->_cmd_randq([], $msg, 'rdb', $rdb, $str)
}

sub _cmd_rdb_searchidx {
  my ($self, $msg, $parsed_args) = @_;

  my ($rdb, $str) = @$parsed_args;
  
  return 'Syntax: rdb searchidx <RDB> <string>' 
    unless $rdb and $str;

  my $indices = $self->_searchidx($msg, 'indexes', $rdb, $str);
  
  ## if we posted out to asyncsearch, return immediately
  return unless ref $indices eq 'ARRAY';

  ## otherwise we should have indices
  $indices->[0] = 'No matches' unless @$indices;
  my $count = @$indices;
  
  my (@returned, $prefix);
  if ($count > 30) {
    @returned = @$indices[0 .. 29];
    $prefix   = "Matches (30 of $count): ";
  } else {
    @returned = @$indices;
    $prefix   = "Matches: ";
  }

  return $prefix.join('  ', @returned);
}
  ### self-events ###

sub Bot_rdb_triggered {
  ## Bot_rdb_triggered $context, $channel, $nick, $rdb
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $channel = ${$_[1]};
  my $nick    = ${$_[2]};
  my $rdb     = ${$_[3]};
  my $orig    = ${$_[4]};
  my $questionstr = ${$_[5]};

  ## event normally triggered by Info3 when a topic references a ~rdb
  ## grab a random response and throw it back at the pipeline
  ## info3 plugin can pick it up and do variable replacement on it 

  core->log->debug("received rdb_triggered");

  my $dbmgr = $self->DBmgr;
  
  ## if referenced rdb doesn't exist, send orig string
  my $send_orig;
  unless ( $dbmgr->dbexists($rdb) ) {
      ++$send_orig;
  }
  
  ## construct fake msg obj for _select_random
  my $new_msg = Bot::Cobalt::IRC::Message::Public->new(
    context => $context,
    src     => $nick . '!fake@host',
    targets => [ $channel ],
    message => '',
  );
  
  my $random = $send_orig ? $orig 
               : $self->_select_random($new_msg, $rdb, 'quietfail') ;

  if (exists core()->Provided->{info_topics}) {
    broadcast( 'info3_relay_string',
      $context, $channel, $nick, $random, $questionstr
    );
  } else {
    logger->warn("RDB plugin cannot trigger, Info3 is missing");
  }
  return PLUGIN_EAT_ALL
}

sub Bot_rdb_broadcast {
  my ($self, $core) = splice @_, 0, 2;
  ## our timer self-event

  my $random = $self->_select_random({}, 'main', 'quietfail')
               || return PLUGIN_EAT_ALL;
  
  ## iterate channels cfg
  ## throw randstuffs at configured channels unless told not to
  my $servers = $core->Servers;
  SERVER: for my $context (keys %$servers) {
    my $c_obj = $core->get_irc_context($context);
    next SERVER unless $c_obj->connected;

    my $irc   = $core->get_irc_obj($context) || next SERVER;
    my $chcfg = $core->get_channels_cfg($context);

    $core->log->debug("rdb_broadcast to $context");

    my $on_channels = $irc->channels || {};
    my $casemap  = $core->get_irc_casemap($context) || 'rfc1459';
    my @channels = map { lc_irc($_, $casemap) } keys %$on_channels;

    my $evtype;
    if ( index($random, '+') == 0 ) {
      ## action
      $random = substr($random, 1);
      $evtype = 'action';
    } else {
      $evtype = 'message';
    }
    
    @channels = grep { $chcfg->{$_}->{rdb_randstuffs}//1 } @channels;

    my $maxtargets = $c_obj->maxtargets;
    
    while (my @targets = splice @channels, 0, $maxtargets) {
      my $tcount = @targets;
      logger->debug(
        "rdb_broadcast ($evtype) to $tcount targets ($context)"
      );
      my $targetstr = join ',', @targets;
      broadcast( $evtype, $context, $targetstr, $random );
    }
    
  } # SERVER

  ## reset timer unless randdelay is 0
  if ($self->rand_delay) {
    $core->timer_set( $self->rand_delay, 
      { 
        Event => 'rdb_broadcast', 
        Alias => $core->get_plugin_alias($self) 
      }, 
      'RANDSTUFF'
    );
  }

  return PLUGIN_EAT_ALL  ## theoretically no one else cares
}


  ### 'worker' methods ###

sub _searchidx {
  my ($self, $msg, $type, $rdb, $string) = @_;
  $rdb   = 'main' unless $rdb;
  $string = '<*>' unless $string;

  my $dbmgr = $self->DBmgr;

  if ( $self->SessionID ) {
    ## if we have asyncsearch, return immediately

    unless ( $dbmgr->dbexists($rdb) ) {
      return rplprintf( core()->lang->{RDB_ERR_NO_SUCH_RDB},
        { nick => $msg->src_nick, rdb => $rdb },
      );
    }
    
    $poe_kernel->post( $self->SessionID,
      'poe_post_search',
      $rdb,
      $string,
      {          ## Hints hash
        Glob     => $string,
        Context  => $msg->context,
        Channel  => $msg->channel,
        Nickname => $msg->src_nick,
        GetType  => $type,
        RDB      => $rdb,
      },
    );
    
    return
  }

  my $ret = $dbmgr->search($rdb, $string);
  
  unless (ref $ret eq 'ARRAY') {
    my $err = $dbmgr->Error;
    core->log->warn("searchidx failure: retval: $err");
    return
  }
  
  ## Return arrayref on success
  return $ret
}

sub _add_item {
  my ($self, $rdb, $item, $username) = @_;
  return unless $rdb and defined $item;
  $username = '-undefined' unless $username;
  
  my $dbmgr = $self->DBmgr;
  unless ( $dbmgr->dbexists($rdb) ) {
    core->log->debug("cannot add item to nonexistant rdb: $rdb");
    return (0, 'RDB_NOSUCH')
  }
  
  my $itemref = [ $item, time(), $username ];

  my $status = $dbmgr->put($rdb, $itemref);
  
  unless ($status) {
    ##   RDB_NOSUCH
    ##   RDB_DBFAIL
    my $err = $dbmgr->Error;
    return (0, $err)
  }

  ## otherwise we should've gotten the new key back:
  my $pref = core->Provided;
  ++$pref->{randstuff_items} if $rdb eq 'main';

  return $status
}

sub _delete_item {
  my ($self, $rdb, $item_idx, $username) = @_;
  return unless $rdb and defined $item_idx;

  my $dbmgr = $self->DBmgr;
  
  unless ( $dbmgr->dbexists($rdb) ) {
    core->log->debug("cannot delete from nonexistant rdb: $rdb");
    return (0, 'RDB_NOSUCH')
  }

  my $status = $dbmgr->del($rdb, $item_idx);
  
  unless ($status) {
    my $err = $dbmgr->Error;
    core->log->debug("cannot _delete_item: $rdb $item_idx ($err)");
    return (0, $err)
  }
  my $pref = core->Provided;
  --$pref->{randstuff_items} if $rdb eq 'main';

  return $item_idx
}


sub _delete_rdb {
  my ($self, $rdb) = @_;
  return unless $rdb;
  my $pcfg = core->get_plugin_cfg( $self );

  my $can_delete = $pcfg->{Opts}->{AllowDelete} // 0;

  unless ($can_delete) {
    core->log->debug("attempted delete but AllowDelete = 0");
    return (0, 'RDB_NOTPERMITTED')
  }

  my $dbmgr = $self->DBmgr;

  unless ( $dbmgr->dbexists($rdb) ) {
    core->log->debug("cannot delete nonexistant rdb $rdb");
    return (0, 'RDB_NOSUCH')
  }

  if ($rdb eq 'main') {
    ## check if this is 'main'
    ##  check core cfg to see if we can delete 'main'
    ##  default to no
    my $can_del_main = $pcfg->{Opts}->{AllowDeleteMain} // 0;
    unless ($can_del_main) {
      core->log->debug(
        "attempted to delete main but AllowDelete Main = 0"
      );
      return (0, 'RDB_NOTPERMITTED')
    }    
  }

  my $status = $dbmgr->deldb($rdb);
  
  unless ($status) {
    my $err = $dbmgr->Error;
    return $err
  }

  return 1
}


## POE

sub _start {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  
  $self->SessionID( $_[SESSION]->ID );
  
  $kernel->alias_set('sess_'. core->get_plugin_alias($self) );
  
  my $maxworkers = core()->get_plugin_cfg($self)->{Opts}->{AsyncSearch};
  $maxworkers = 5 unless $maxworkers > 1;
  
  ## spawn asyncsearch sess
  require Bot::Cobalt::Plugin::RDB::AsyncSearch;
  
  my $asid = Bot::Cobalt::Plugin::RDB::AsyncSearch->spawn(
    MaxWorkers  => $maxworkers,
    ResultEvent => 'poe_got_result',
    ErrorEvent  => 'poe_got_error',
  );
  
  $self->AsyncSessionID( $asid );
}

sub poe_post_search {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my ($rdbname, $globstr, $hintshash) = @_[ARG0 .. $#_];

  logger->debug("Posting async search ($rdbname)");

  ## compose rdb path
  my $cfg = core->get_plugin_cfg($self);

  my $rdbdir = File::Spec->catdir(
    core()->var,
    $cfg->{Opts}->{RDBDir} ? $cfg->{Opts}->{RDBDir} : ('db', 'rdb')
  );
  
  my $rdbpath = File::Spec->catfile( $rdbdir, "$rdbname.rdb" );
  
  my $dbmgr = $self->DBmgr;
  
  if (my @matches = $dbmgr->cache_check($rdbname, $globstr) ) {
    ## have cached results in ::Database's cache
    ## yield back to ourselves and return
    $kernel->post( $_[SESSION], 'poe_got_result',
      \@matches,
      $hintshash,
    );
    return
  }
  
  my $re = glob_to_re_str($globstr);
  
  ## post a search w / hintshash
  $kernel->post( $self->AsyncSessionID, 
    'search_rdb',
    $rdbpath,
    $re,
    $hintshash
  );
}

sub poe_got_result {
  my ($self, $kernel, $heap)  = @_[OBJECT, KERNEL, HEAP];
  my ($resultarr, $hintshash) = @_[ARG0, ARG1];
  
  my $context  = $hintshash->{Context};
  my $channel  = $hintshash->{Channel};
  my $nickname = $hintshash->{Nickname};
  ## type is: string, indexes, or count
  ##  (aka: randq / rdb search, rdb searchidx, rdb count)
  my $type     = $hintshash->{GetType}; 
  my $glob     = $hintshash->{Glob};
  my $rdb      = $hintshash->{RDB};

  logger->debug("Received async search response ($rdb)");
  
  my $resp;
  
  my $dbmgr = $self->DBmgr;
  
  given ($type) {

    when ("string") {
      unless (@$resultarr) {
        $resp = "$nickname: No matches found for $glob";
      } else {
        ## cachable, we get a full set back
        $dbmgr->cache_push($rdb, $glob, $resultarr);
      
        my $itemkey = $resultarr->[rand @$resultarr];
        my $item    = $dbmgr->get($rdb, $itemkey);
        
        unless ($item && ref $item) {
          my $err = $dbmgr->Error;
          logger->warn("Error from get(): $err");
          my $rpl = $err eq 'RDB_NOSUCH_ITEM' ?
                      'RDB_ERR_NO_SUCH_ITEM'
                    : 'RPL_DB_ERR' ;
          $resp = rplprintf( core()->lang->{$rpl},
            { nick => $nickname, rdb => $rdb, index => $itemkey }
          );
        } else {
          my $content = ref $item eq 'HASH' ?
                          $item->{String}
                        : $item->[0] ;
          $content = '(undef - broken db?)' unless defined $content;
          $resp = "[$itemkey] $content";
        }
        
      }
    }
    
    when ("indexes") {
      unless (@$resultarr) {
        $resp = "$nickname: No matches found for $glob";
      } else {
        $dbmgr->cache_push($rdb, $glob, $resultarr);
      
        my $count = @$resultarr;
        
        my (@returned, $prefix);
        
        if ($count > 30) {
          @returned = (shuffle @$resultarr)[0 .. 29];
          $prefix   = "$nickname: matches (30 / $count): ";
        } else {
          @returned = @$resultarr;
          $prefix   = "$nickname: matches ($count): ";
        }
        
        $resp = $prefix . join('  ', @returned);
      }
    }
    
    when ("count") {
      $dbmgr->cache_push($rdb, $glob, $resultarr)
        if @$resultarr;

      my $count = @$resultarr;
      $resp = "$nickname: Found $count matches for $glob";
    }
  
  }
  
  broadcast( 'message', $context, $channel, $resp ) if $resp;
}  

sub poe_got_error {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my ($error, $hints) = @_[ARG0, ARG1];
  
  my $glob = $hints->{Glob};
  my $rdb  = $hints->{RDB};
  
  logger->warn("Received error from AsyncSearch: $rdb ($glob): $error");
  
  my $context  = $hints->{Context};
  my $channel  = $hints->{Channel};
  my $nickname = $hints->{Nickname};
  
  broadcast( 'message', $context, $channel,
    "$nickname: asyncsearch error: $error ($rdb)"
  );
}


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Plugin::RDB - Cobalt "random stuff" plugin

=head1 DESCRIPTION

Jason Hamilton's B<darkbot> came with the concept of "randstuffs," 
randomized responses broadcast to channels via a timer.

Later versions included a search interface and "RDBs" -- discrete 
'randstuff' databases that could be accessed via 'info' topic triggers 
to return a random response.

B<cobalt1> used essentially the same interface.
This B<RDB> plugin attempts to expand on that concept.

This functionality is often useful to simulate humanoid responses to 
conversation (by writing 'conversational' RDB replies triggered by 
L<Bot::Cobalt::Plugin::Info3> topics), to implement IRC quotebots, or just 
to fill your channel with random chatter.

The "randstuff" db is labelled "main" -- all other RDB names must be 
in the [a-z0-9] set.

Requires L<Bot::Cobalt::Plugin::Info3>.

=head1 COMMANDS

Commands are prefixed with the bot's nickname, rather than CmdChar.

This is a holdover from darkbot legacy syntax.

  <JoeUser> botnick: randq some*glob

=head2 randq

Search for a specified glob in RDB 'main' (randstuffs):

  <JoeUser> bot: randq some+string*

See L<Bot::Cobalt::Utils/glob_to_re_str> for details regarding glob syntax.


=head2 randstuff

Add a new "randstuff" to the 'main' RDB

  <JoeUser> bot: randstuff new randstuff string

A randstuff can also be an action; simply prefix the string with B<+> :

  <JoeUser> bot: randstuff +dances around

Legacy darkbot-style syntax is supported; you can add items to RDBs 
by prefixing the RDB name with B<~>, like so:

  randstuff ~myrdb some new string

The RDB must already exist; see L</"rdb dbadd">

=head2 rdb

=head3 rdb info

  rdb info <rdb>
  rdb info <rdb> <itemID>

Given just a RDB name, returns the number of items in the RDB.

Given a RDB name and a valid itemID, returns some metadata regarding the 
item, including the username that added it and the date it was added.

=head3 rdb add

  rdb add <rdb> <new item string>

Add a new item to the specified RDB. Also see L</randstuff>

=head3 rdb del

  rdb del <rdb> <itemID>

Deletes an item from the specified RDB by item index ID.

=head3 rdb dbadd

  rdb dbadd <rdb>

Creates a new, empty RDB.

=head3 rdb dbdel

  rdb dbdel <rdb>

Deletes the specified RDB entirely.

Deletion may be disabled in the plugin's configuration file via the 
B<< Opts->AllowDelete >> directive.

=head3 rdb search

  rdb search <rdb> <glob>

Search within a specific RDB. Returns a single random response from the 
result set.

=head3 rdb searchidx

  rdb searchidx <rdb> <glob>

Returns all RDB item IDs matching the specified glob.

=head3 rdb count

  rdb count <rdb> <glob>

Returns just the total number of matches for the specified glob.

=head2 random

'random' is not actually a built-in command; however, since you must have 
L<Bot::Cobalt::Plugin::Info3>, a handy trick is to add a topic named 'random' 
that triggers RDB 'main':

  <JoeUser> bot: add random ~main

That will allow use of 'random' to pull a randomly-selected entry from the 
'randstuffs' database.


=head1 EVENTS

=head2 Received events

=head3 rdb_broadcast

Self-triggered event.

Called on a timer to broadcast randstuffs from RDB "main."

Takes no arguments.

=head3 rdb_triggered

Triggered (usually by L<Bot::Cobalt::Plugin::Info3>) when a RDB is polled 
for a random response.

Arguments are:

  $context, $channel, $nick, $rdb, $topic_value, $original_str

Broadcasts an L</info3_relay_string> in response, which is picked up by 
B<Info3> to perform variable replacement before relaying back to the 
calling channel.

=head2 Emitted events

=head3 info3_relay_string

Broadcast by L</rdb_triggered> to be picked up by L<Bot::Cobalt::Plugin::Info3>.

Arguments are:

  $context, $channel, $nick, $string, $original

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
