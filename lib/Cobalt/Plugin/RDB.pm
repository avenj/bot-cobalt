package Cobalt::Plugin::RDB;
our $VERSION = '0.310';

## 'Random' DBs, often used for quotebots or random chatter
##
## This plugin mostly ties together the Plugin::RDB::* modules 
## and translates Plugin::RDB::Constant return values back to 
## rplprintf()-formatted IRC replies

## Hash for a RDB item:
##   String => "string",
##   AddedAt => time(),
##   AddedBy => $username,
##   },

use 5.10.1;

use Cobalt::Common;

use Cobalt::Plugin::RDB::Database;

## marked non-reloadable .. shouldfix
## ought to feed our external RDB:: modules to unloader_cleanup
sub new { bless { NON_RELOADABLE => 1 }, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;

  $core->plugin_register($self, 'SERVER',
    [ 
      'public_msg',
      'rdb_broadcast',
      'rdb_triggered',
    ],
  );  

  my $cfg = $core->get_plugin_cfg( $self );

  my $cachekeys = $cfg->{Opts}->{CacheItems} // 30;

  my $rdbdir = $core->var ."/". ($cfg->{Opts}->{RDBDir} || "db/rdb");
  ## if the rdbdir doesn't exist, ::Database will try to create it
  ## (it'll also handle creating 'main' for us)
  my $dbmgr = Cobalt::Plugin::RDB::Database->new(
    CacheKeys => $cachekeys,
    RDBDir    => $rdbdir,
    core => $core,
  );
  $core->log->debug("Created RDB manager instance");
  $self->{CDBM} = $dbmgr;

  my $keys_c = $dbmgr->get_keys('main');
  $core->Provided->{randstuff_items} = $keys_c;
  $core->log->debug("initialized: $keys_c main RDB keys");

  ## kickstart a randstuff timer (named timer for rdb_broadcast)
  ## delay is in Opts->RandDelay as a timestr
  ## (0 turns off timer)
  my $randdelay = $cfg->{Opts}->{RandDelay} // '30m';
  $core->log->debug("randdelay: $randdelay");
  $randdelay = timestr_to_secs($randdelay) unless $randdelay =~ /^\d+$/;
  $self->{RandDelay} = $randdelay;
  if ($randdelay) {
    $core->timer_set( $randdelay, 
      { 
        Event => 'rdb_broadcast', 
        Alias => $core->get_plugin_alias($self) 
      }, 
      'RANDSTUFF'
    );
  }

  $core->log->info("Registered - $VERSION");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistering random stuff");
  delete $core->Provided->{randstuff_items};
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
  ## FIXME: document this behavior
  my $msg_arr = $msg->message_array_sp;
  ## since this is a highlighted message, bot's nickname is first
  my ($cmd, @message) = @$msg_arr[1 .. (scalar @$msg_arr - 1)];
  $cmd = lc($cmd||'');
  ## ..if it's not @handled we don't care:
  return PLUGIN_EAT_NONE unless $cmd and $cmd ~~ @handled;

  $core->log->debug("Dispatching $cmd");

  ## dispatcher:
  my ($id, $resp);
  given ($cmd) {
    $resp = $self->_cmd_randstuff(\@message, $msg)
      when "randstuff";
    $resp = $self->_cmd_randq(\@message, $msg, 'randq')
      when "randq";
    $resp = $self->_cmd_rdb(\@message, $msg)
      when "rdb";
  }
  
  $resp = "No output for $cmd - BUG!" unless $resp;

  my $channel = $msg->channel;
  $core->log->debug("dispatching msg -> $channel");
  $core->send_event( 'send_message', $context, $channel, $resp );

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

  my $core = $self->{core};
  my $pcfg = $core->get_plugin_cfg( $self );
  my $required_level = $pcfg->{RequiredLevels}->{rdb_add_item} // 1;

  my $rplvars;
  $rplvars->{nick} = $src_nick;

  unless ( $core->auth_level($context, $src_nick) >= $required_level ) {
    return rplprintf( $core->lang->{RPL_NO_ACCESS}, $rplvars );
  }
  
  my $rdb = 'main';      # randstuff is 'main', darkbot legacy
  $rplvars->{rdb} = $rdb;
  ## ...but this may be randstuff ~rdb ... syntax:
  if (@message && index($message[0], '~') == 0) {
    $rdb = substr(shift @message, 1);
    $rplvars->{rdb} = $rdb;
    my $dbmgr = $self->{CDBM};
    unless ($rdb && $dbmgr->dbexists($rdb) ) {
      ## ~rdb specified but nonexistant
      return rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB}, $rplvars );
    }
  }

  ## should have just the randstuff itself now (and maybe a different rdb):
  my $randstuff_str = join ' ', @message;
  $randstuff_str = decode_irc($randstuff_str);

  unless ($randstuff_str) {
    return rplprintf( $core->lang->{RDB_ERR_NO_STRING}, $rplvars );
  }

  ## call _add_item
  my $username = $core->auth_username($context, $src_nick);
  my ($newidx, $err) =
    $self->_add_item($rdb, $randstuff_str, $username);
  $rplvars->{index} = $newidx;
  ## _add_item returns either a status from ::Database->put
  ## or a new item key:

  unless ($newidx) {
    given ($err) {
      return rplprintf( $core->lang->{RPL_DB_ERR}, $rplvars )
        when "RDB_DBFAIL";
      
      return rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB}, $rplvars )
        when "RDB_NOSUCH";
      
      default { return "Unknown error status: $err" }
    }
  } else {
    return rplprintf( $core->lang->{RDB_ITEM_ADDED}, $rplvars );
  }
  
}

sub _select_random {
  my ($self, $msg, $rdb, $quietfail) = @_;
  my $core   = $self->{core};
  my $dbmgr  = $self->{CDBM};
  my $retval = $dbmgr->random($rdb);
  ## we'll get either an item as hashref or err status:
  
  if ($retval && ref $retval eq 'HASH') {
    my $content = $retval->{String} // '';
    if ($self->{LastRandom}
        && $self->{LastRandom} eq $content
    ) {
      $retval  = $dbmgr->random($rdb);
      $content = $retval->{String}//''
        if ref $retval eq 'HASH';
    }
    $self->{LastRandom} = $content;
    return $content
  } else {
    ## do nothing if we're supposed to fail quietly
    ## (e.g. in a rdb_triggered for a bustedass rdb)
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
    return rplprintf( $core->lang->{$rpl},
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
  my $dbmgr = $self->{CDBM};
  my $core  = $self->{core};

  my($str, $rdb);
  if    ($type eq 'random') {
    ## FIXME this is actually deprecated
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

  $core->log->debug("dispatching search for $str in $rdb");

  my $matches = $dbmgr->search($rdb, $str);

  unless ($matches && ref $matches eq 'ARRAY') {
    $core->log->debug("Error status from search(): $matches");
    my $rpl;
    given ($dbmgr->Error) {
      $rpl = "RPL_DB_ERR"          when "RDB_DBFAIL";
      $rpl = "RDB_ERR_NO_SUCH_RDB" when "RDB_NOSUCH";
      ## not an arrayref and not a known error status, wtf?
      default { $rpl = "RPL_DB_ERR" }
    }
    return rplprintf( $core->lang->{$rpl},
      { nick => $msg->src_nick, rdb => $rdb }
    );
  }

  ## pick one at random:
  my $selection = @$matches ? 
                   @$matches[rand @$matches]
                   : return 'No match' ;
  
  if ($self->{LastRandq} 
      && $self->{LastRandq} eq $selection 
      && @$matches > 1) 
  {
    ## we probably just spit this randq out
    ## give it one more shot
    $selection = @$matches[rand@$matches];
  }
  $self->{LastRandq} = $selection;

  $core->log->debug("dispatching get() for $selection in $rdb");

  my $item = $dbmgr->get($rdb, $selection);
  unless ($item && ref $item eq 'HASH') {
    $core->log->debug("Error status from get(): $item");
    my $rpl;
    given ($dbmgr->Error) {
      $rpl = "RDB_ERR_NO_SUCH_ITEM" when "RDB_NOSUCH_ITEM";
      ## an unknown non-hashref $item is also a DB_ERR:
      default { "RPL_DB_ERR" }
    }
    return rplprintf( $core->lang->{$rpl},
      { 
        nick  => $msg->src_nick//'',
        rdb   => $rdb, 
        index => $selection 
      }
    );
  }

  my $content = $item->{String} // '(undef - broken db!)';
  my $itemkey = $item->{DBKEY}  // '(undef - broken db!)';
  
  return "[${itemkey}] $content" ;
}


sub _cmd_rdb {
  ## cmd handler for:
  ##   rdb add
  ##   rdb del
  ##   rdb get 
  ##   rdb dbadd
  ##   rdb dbdel
  ##   rdb info
  ##   rdb search
  ##   rdb searchidx
  ## FIXME rdb dblist
  ## this got out of hand fast.
  ## really needs to be dispatched out, badly.
  my ($self, $parsed_msg_a, $msg) = @_;
  my $core = $self->{core};
  my @message = @{ $parsed_msg_a };

  my $pcfg = $core->get_plugin_cfg( $self );
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
  my $user_lev = $core->auth_level($context, $nickname) // 0;
  my $username = $core->auth_username($context, $nickname);
  unless ($user_lev >= $access_levs{$cmd}) {
    return rplprintf( $core->lang->{RPL_NO_ACCESS},
      { nick => $nickname }
    );
  }

  my $dbmgr = $self->{CDBM};

  my $resp;
  given ($cmd) {

    when ("dbadd") {
      ## _create a new rdb if it doesn't exist
      my ($rdb) = @message;
      return 'Syntax: rdb dbadd <RDB>' unless $rdb;
      
      return 'RDB name must be in the a-z0-9 set'
        unless $rdb =~ /^[a-z0-9]+$/;

      return 'RDB name must be less than 32 characters'
        unless length $rdb <= 32;

      my $retval = $dbmgr->createdb($rdb);

      my $rplvars = {
        nick => $nickname,
        rdb  => $rdb,
        op  => $cmd,
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
      
      return rplprintf( $core->lang->{$rpl}, $rplvars );
    }

    when ("dbdel") {
      ## delete a rdb if we're allowed (per conf and requiredlev)
      my ($rdb) = @message;
      return 'Syntax: rdb dbdel <RDB>' unless $rdb;
      
      my $rplvars = {
        nick => $nickname,
        rdb  => $rdb,
        op   => $cmd,
      };

      my ($retval, $err) = $self->_delete_rdb($rdb);
      
      my $rpl;
      if ($retval) {
        $rpl = "RDB_DELETED";
      } else {
        ## FIXME handle retvals from _delete_rdb
        ## _delete_rdb should act like Database.pm
        given ($err) {
          $rpl = "RDB_ERR_NOTPERMITTED" when "RDB_NOTPERMITTED";
          $rpl = "RDB_ERR_NO_SUCH_RDB"  when "RDB_NOSUCH";
          $rpl = "RPL_DB_ERR"           when "RDB_DBFAIL";
          $rpl = "RDB_UNLINK_FAILED"    when "RDB_FILEFAILURE";
          default { return "Unknown err $err from _delete_rdb" }
        }
      }
      
      return rplprintf( $core->lang->{$rpl}, $rplvars );
    }
    
    when ("add") {
      my ($rdb, @items) = @message;
      my $item = join ' ', @items;
      return 'Syntax: rdb add <RDB> <item>' unless $rdb and $item;

      my $rplvars = {
        nick => $nickname,
        rdb  => $rdb,
      };

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

      return rplprintf( $core->lang->{$rpl}, $rplvars );
    }
    
    when ("del") {
      my ($rdb, $item_idx) = @message;
      return 'Syntax: rdb del <RDB> <index number>'
        unless $rdb and $item_idx;

      my $rplvars = {
        nick => $nickname,
        rdb  => $rdb,
        index => $item_idx,
      };

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

      return rplprintf( $core->lang->{$rpl}, $rplvars ) ;      
    }

    when ("get") {
      my ($rdb, $idx) = @message;
      return 'Syntax: rdb get <RDB> <index key>'
        unless $rdb and $idx;

      my $rplvars = {
        nick => $nickname,
        rdb  => $rdb,
        index => $idx,
      };
      
      my $dbmgr = $self->{CDBM};
      unless ( $dbmgr->dbexists($rdb) ) {
        return rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB}, $rplvars );
      }
      
      my $item = $dbmgr->get($rdb, $idx);

      if ($item and ref $item eq 'HASH') {
        my $indexkey = $item->{DBKEY}  // '(undef)';
        my $content  = $item->{String} // '(undef)';
        return "[${indexkey}] $content"
      } else {
        my $err = $dbmgr->Error || 'Unknown error';
        my $rpl;
        given ($err) {
          $rpl = "RDB_ERR_NO_SUCH_ITEM"  when "RDB_NOSUCH_ITEM";
          $rpl = "RDB_ERR_NO_SUCH_RDB"   when "RDB_NOSUCH";
          $rpl = "RPL_DB_ERR"            when "RDB_DBFAIL";
          default { return "Error: $err" }
        }
        return rplprintf( $core->lang->{$rpl}, $rplvars );
      }

    }

    when ("info") {
      ## return metadata about an item by rdb and index number
      my ($rdb, $idx) = @message;
      return 'Syntax: rdb info <RDB> <index key>'
        unless $rdb;
      
      my $dbmgr = $self->{CDBM};

      my $rplvars = {
        nick => $nickname,
        rdb  => $rdb,
      };

      return rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB}, $rplvars )
        unless $dbmgr->dbexists($rdb);

      unless ($idx) {
        my $n_keys = $dbmgr->get_keys($rdb);
        return "RDB $rdb has $n_keys items"
      }
      
      $rplvars->{index} = $idx;

      my $item = $dbmgr->get($rdb, $idx);
      unless ($item && ref $item eq 'HASH') {
        my $err = $dbmgr->Error || 'Unknown error';
        my $rpl;
        given ($err) {
          $rpl = "RDB_ERR_NO_SUCH_ITEM" when "RDB_NOSUCH_ITEM";
          $rpl = "RDB_ERR_NO_SUCH_RDB"  when "RDB_NOSUCH";
          $rpl = "RPL_DB_ERR"           when "RDB_DBFAIL";
          default { return "Error: $err" }
        }
        return rplprintf( $core->lang->{$rpl}, $rplvars );
      }

      my $added_dt = DateTime->from_epoch(
        epoch => $item->{AddedAt} // 0
      );
      my $added_by = $item->{AddedBy} // '(undef)';
  
      $rplvars = {
        nick  => $nickname,
        rdb   => $rdb,
        index => $idx,
        date  => $added_dt->date,
        time  => $added_dt->time,
        addedby => $added_by,
      };

      $resp = rplprintf( $core->lang->{RDB_ITEM_INFO}, $rplvars );
    }

    when ("search") {
      ## search by rdb and string
      ## parse, call _cmd_randq and just pass off to that
      my ($rdb, $str) = @message;
      $str = '*' unless $str;
      return 'Syntax: rdb search <RDB> <string>' unless $rdb;

      $resp = $self->_cmd_randq([], $msg, 'rdb', $rdb, $str)
    }
    
    when ("searchidx") {
      my ($rdb, $str) = @message;
      return 'Syntax: rdb searchidx <RDB> <string>' 
        unless $rdb and $str;
      my @indices = $self->_searchidx($rdb, $str);
      $indices[0] = 'No matches' unless @indices;
      my @returned = scalar @indices > 30 ? @indices[0 .. 29] : @indices ;
      $resp = "Matches (max 30): ".join('  ', @returned);
    }
    
    when ("count") {
      my ($rdb, $str) = @message;
      return 'Syntax: rdb count <RDB> <str>'
        unless $rdb and $str;
      my @indices = $self->_searchidx($rdb, $str);
      my $count = scalar @indices;
      $resp = "${nickname}: Found $count matches";
    }

  }

  return $resp;
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

  $core->log->debug("received rdb_triggered");

  my $dbmgr = $self->{CDBM};
  
  ## if referenced rdb doesn't exist, send orig string
  my $send_orig;
  unless ( $dbmgr->dbexists($rdb) ) {
      ++$send_orig;
  }
  
  ## construct fake msg obj for _select_random
  my $new_msg = Cobalt::IRC::Message::Public->new(
    core    => $core,
    context => $context,
    src     => $nick . '!fake@host',
    targets => [ $channel ],
    message => '',
  );
  
  my $random = $send_orig ? $orig 
               : $self->_select_random($new_msg, $rdb, 'quietfail') ;

  $core->send_event( 
    'info3_relay_string', $context, $channel, $nick, $random, $questionstr
  );

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
    my $c_hash = $core->get_irc_context($context);
    next SERVER unless $c_hash->{Connected};
    my $irc = $core->get_irc_obj($context) || next SERVER;
    my $chcfg = $core->get_channels_cfg($context);

    $core->log->debug("rdb_broadcast to $context");

    my $on_channels = $irc->channels || {};
    my $casemap = $core->get_irc_casemap($context) || 'rfc1459';
    my @channels = map { lc_irc($_, $casemap) } keys %$on_channels;

    CHAN: for my $channel (@channels) {
      next CHAN if ($chcfg->{$channel}->{rdb_randstuffs}//1) == 0;
 
      ## action/msg check   
      if ( index($random, '+') == 0 ) {
        my $random_action = substr($random, 1);
        $core->log->debug(
          "rdb_broadcast (action) -> $context -> $channel"
        );
        $core->send_event( 'send_action', $context, $channel, $random_action );
      } else {
        $core->log->debug("rdb_broadcast -> $context -> $channel");
        $core->send_event( 'send_message', $context, $channel, $random );
      }
 
    } # CHAN
  } # SERVER

  ## reset timer unless randdelay is 0
  if ($self->{RandDelay}) {
    $core->timer_set( $self->{RandDelay}, 
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
  my ($self, $rdb, $string) = @_;
  $rdb   = 'main' unless $rdb;
  $string = '<*>' unless $string;

  my $dbmgr = $self->{CDBM};
  my $ret = $dbmgr->search($rdb, $string);
  
  unless (ref $ret eq 'ARRAY') {
    my $err = $dbmgr->Error;
    $self->{core}->log->warn("searchidx failure: retval: $err");
    return wantarray ? () : $err ;
  }
  return wantarray ? @$ret : $ret ;
}

sub _add_item {
  my ($self, $rdb, $item, $username) = @_;
  return unless $rdb and defined $item;
  my $core = $self->{core};
  $username = '-undefined' unless $username;
  
  my $dbmgr = $self->{CDBM};
  unless ( $dbmgr->dbexists($rdb) ) {
    $core->log->debug("cannot add item to nonexistant rdb: $rdb");
    return (0, 'RDB_NOSUCH')
  }
  
  my $itemref = {
    AddedBy => $username,
    AddedAt => time,
    String  => $item,
  };

  my $status = $dbmgr->put($rdb, $itemref);
  
  unless ($status) {
    ##   RDB_NOSUCH
    ##   RDB_DBFAIL
    my $err = $dbmgr->Error;
    return (0, $err)
  }

  ## otherwise we should've gotten the new key back:
  ++$core->Provided->{randstuff_items} if $rdb eq 'main';
  return $status
}

sub _delete_item {
  my ($self, $rdb, $item_idx, $username) = @_;
  return unless $rdb and defined $item_idx;
  my $core = $self->{core};

  my $dbmgr = $self->{CDBM};
  
  unless ( $dbmgr->dbexists($rdb) ) {
    $core->log->debug("cannot delete from nonexistant rdb: $rdb");
    return (0, 'RDB_NOSUCH')
  }

  my $status = $dbmgr->del($rdb, $item_idx);
  
  unless ($status) {
    my $err = $dbmgr->Error;
    $core->log->debug("cannot _delete_item: $rdb $item_idx ($err)");
    return (0, $err)
  }

  --$core->Provided->{randstuff_items} if $rdb eq 'main';
  return $item_idx
}


sub _delete_rdb {
  my ($self, $rdb) = @_;
  return unless $rdb;
  my $core = $self->{core};
  my $pcfg = $core->get_plugin_cfg( $self );

  my $can_delete = $pcfg->{Opts}->{AllowDelete} // 0;

  unless ($can_delete) {
    $core->log->debug("attempted delete but AllowDelete = 0");
    return (0, 'RDB_NOTPERMITTED')
  }

  my $dbmgr = $self->{CDBM};

  unless ( $dbmgr->dbexists($rdb) ) {
    $core->log->debug("cannot delete nonexistant rdb $rdb");
    return (0, 'RDB_NOSUCH')
  }

  if ($rdb eq 'main') {
    ## check if this is 'main'
    ##  check core cfg to see if we can delete 'main'
    ##  default to no
    my $can_del_main = $pcfg->{Opts}->{AllowDeleteMain} // 0;
    unless ($can_del_main) {
      $core->log->debug(
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


1;
__END__

=pod

=head1 NAME

Cobalt::Plugin::RDB - "random stuff" plugin

=head1 DESCRIPTION

Jason Hamilton's B<darkbot> came with the concept of "randstuffs," 
randomized responses broadcast to channels via a timer.

Later versions included a search interface and "RDBs" -- discrete 
'randstuff' databases that could be accessed via 'info' topic triggers 
to return a random response.

B<cobalt1> used essentially the same interface.
This B<RDB> plugin attempts to expand on that functionality.

This functionality is often useful to simulate humanoid responses to 
conversation (by writing 'conversational' RDB replies triggered by 
L<Cobalt::Plugin::Info3> topics), to implement IRC quotebots, or just 
to fill your channel with random chatter.

The "randstuff" db is labelled "main" -- all other RDB names must be 
in the [a-z0-9] set.

=head1 COMMANDS

Commands are prefixed with the bot's nickname, rather than CmdChar.

This is a holdover from darkbot legacy syntax.

  <JoeUser> botnick: randq some*glob

=head2 randq

Search for a specified glob in RDB 'main' (randstuffs):

  <JoeUser> bot: randq some+string*

See L<Cobalt::Utils/glob_to_re_str> for details regarding glob syntax.


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

'random' is not actually a built-in command; however, assuming you have 
L<Cobalt::Plugin::Info3>, a handy trick is to add a topic named 'random' 
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

Triggered (usually by L<Cobalt::Plugin::Info3>) when a RDB is polled 
for a random response.

Arguments are:

  $context, $channel, $nick, $rdb, $topic_value, $original_str

Broadcasts an L</info3_relay_string> in response, which is picked up by 
B<Info3> to perform variable replacement before relaying back to the 
calling channel.

=head2 Emitted events

=head3 info3_relay_string

Broadcast by L</rdb_triggered> to be picked up by L<Cobalt::Plugin::Info3>.

Arguments are:

  $context, $channel, $nick, $string, $original

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
