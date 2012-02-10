package Cobalt::Plugin::RDB;
our $VERSION = '0.24';

## 'Random' DBs, often used for quotebots or random chatter
##
## This plugin mostly ties together the Plugin::RDB::* modules 
## and translates Plugin::RDB::Constant return values back to 
## rplprintf()-formatted IRC replies

## Hash for a RDB item:
##   String => "string",
##   AddedAt => time(),
##   AddedBy => $username,
##   Votes => {
##     Up   => 0,
##     Down => 0,
##   },

## FIXME: voting

use Cobalt::Common;

use Cobalt::Plugin::RDB::Constants;
use Cobalt::Plugin::RDB::Database;


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

  my $cfg = $core->get_plugin_cfg( __PACKAGE__ );

  my $rdbdir =    $core->var ."/". $cfg->{Opts}->{RDBDir} 
               || $core->var ."/db/rdb" ;
  ## if the rdbdir doesn't exist, ::Database will try to create it
  ## (it'll also handle creating 'main' for us)
  my $dbmgr = Cobalt::Plugin::RDB::Database->new(
    RDBDir => $rdbdir,
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
      { Event => 'rdb_broadcast' }, 
      'RANDSTUFF'
    );
  }

  $core->log->info("Registered");
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
  my $context = ${$_[0]};
  my $msg     = ${$_[1]};

  my @handled = qw/
    randstuff
    randq
    random
    rdb    
  /;

  ## would be better in a public_cmd_, but eh, darkbot legacy syntax..
  return PLUGIN_EAT_NONE unless $msg->{highlight};
  ## since this is a highlighted message, bot's nickname is first:
  my @message = @{ $msg->{message_array} };
  shift @message;
  my $cmd = lc(shift @message || '');
  ## ..if it's not @handled we don't care:
  return PLUGIN_EAT_NONE unless $cmd and $cmd ~~ @handled;

  $core->log->debug("Dispatching $cmd");

  ## dispatcher:
  my $resp;
  given ($cmd) {
    $resp = $self->_cmd_randstuff(\@message, $msg)
      when "randstuff";
    $resp = $self->_cmd_randq(\@message, $msg, 'randq')
      when "randq";
    $resp = $self->_cmd_randq(\@message, $msg, 'random')
      when "random";
    $resp = $self->_cmd_rdb(\@message, $msg)
      when "rdb";
  }
  
  $resp = "No output for $cmd - BUG!" unless $resp;

  my $channel = $msg->{channel};
  if (
      $cmd ~~ [ 'randq', 'random' ]
      && index($resp, '+') == 0
  ) {
    $resp = substr($resp, 1);
    $core->log->debug("dispatching action -> $channel");
    $core->send_event( 'send_action', $context, $channel, $resp );
  } else {
    $core->log->debug("dispatching msg -> $channel");
    $core->send_event( 'send_message', $context, $channel, $resp );
  }
  
  return PLUGIN_EAT_NONE
}


  ### command handlers ###

sub _cmd_randstuff {
  ## $parsed_msg_a  == message_array without prefix/cmd
  ## $msg_h == original message hashref
  my ($self, $parsed_msg_a, $msg_h) = @_;
  my @message = @{ $parsed_msg_a };
  my $src_nick = $msg_h->{src_nick};
  my $context  = $msg_h->{context};

  my $core = $self->{core};
  my $pcfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $required_level = $pcfg->{RequiredLevels}->{rdb_add_item} // 1;

  unless ( $core->auth_level($context, $src_nick) >= $required_level ) {
    return rplprintf( $core->lang->{RPL_NO_ACCESS},
      { nick => $src_nick }
    );
  }
  
  my $rdb = 'main';      # randstuff is 'main', darkbot legacy
  ## ...but this may be randstuff ~rdb ... syntax:
  if (index($message[0], '~') == 0) {
    $rdb = substr(shift @message, 1);
    my $dbmgr = $self->{CDBM};
    unless ($rdb && $dbmgr->dbexists($rdb) ) {
      ## ~rdb specified but nonexistant
      return rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB},
        {
          nick => $src_nick,
          rdb  => $rdb,
        }
      );
    }
  }

  ## should have just the randstuff itself now (and maybe a different rdb):
  my $randstuff_str = join ' ', @message;
  $randstuff_str = decode_irc($randstuff_str);

  unless ($randstuff_str) {
    return rplprintf( $core->lang->{RDB_ERR_NO_STRING},
      { nick => $src_nick, rdb  => $rdb }
    );
  }

  ## call _add_item
  my $username = $core->auth_username($context, $src_nick);
  my $newidx = $self->_add_item($rdb, $randstuff_str, $username);

  ## _add_item returns either a status from ::Database->put
  ## or a new item key:
  given ($newidx) {
    when ([RDB_DBFAIL]) {
      return rplprintf( $core->lang->{RPL_DB_ERR} );
    }
    
    when ([RDB_NOSUCH]) {
      return rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB},
        { nick => $src_nick, rdb => $rdb }
      );
    }
    
    default {
      return rplprintf( $core->lang->{RDB_ITEM_ADDED},
        { nick => $src_nick, rdb => $rdb, index => $newidx }
      );
    }
  }

}

sub _select_random {
  my ($self, $msg_h, $rdb, $quietfail) = @_;
  my $core   = $self->{core};
  my $dbmgr  = $self->{CDBM};
  my $retval = $dbmgr->random($rdb);
  ## we'll get either an item as hashref or err status:
  
  if (ref $retval eq 'HASH') {
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
    given ($retval) {
      $rpl = "RDB_ERR_NO_SUCH_RDB" when [RDB_NOSUCH];
      $rpl = "RPL_DB_ERR"          when [RDB_DBFAIL];
      ## send nothing if this rdb has no keys:
      return                       when [RDB_NOSUCH_ITEM];
      ## unknown error status?
      default { $rpl = "RPL_DB_ERR" }
    }
    return rplprintf( $core->lang->{$rpl},
      {
        nick => $msg_h->{src_nick}//'',
        rdb  => $rdb,
      },
    );
  }
}


sub _cmd_randq {
  my ($self, $parsed_msg_a, $msg_h, $type, $rdbpassed, $strpassed) = @_;
  my @message = @{ $parsed_msg_a };

  ## also handler for 'rdb search rdb str'
  my $dbmgr = $self->{CDBM};
  my $core  = $self->{core};

  my($str, $rdb);
  if    ($type eq 'random') {
    ## FIXME allow random <rdb> syntax
    ## dispatch out to _cmd_random
    ## shouldfix; holdovers from 0.10
    return $self->_select_random($msg_h, 'main');
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

  unless (ref $matches eq 'ARRAY') {
    $core->log->debug("Error status from search(): $matches");
    my $rpl;
    given ($matches) {
      $rpl = "RPL_DB_ERR"          when [RDB_DBFAIL];
      $rpl = "RDB_ERR_NO_SUCH_RDB" when [RDB_NOSUCH];
      ## not an arrayref and not a known error status, wtf?
      default { $rpl = "RPL_DB_ERR" }
    }
    return rplprintf( $core->lang->{$rpl},
      { nick => $msg_h->{src_nick}, rdb => $rdb }
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
  unless (ref $item eq 'HASH') {
    $core->log->debug("Error status from get(): $item");
    my $rpl;
    given ($item) {
      $rpl = "RDB_ERR_NO_SUCH_ITEM" when [RDB_NOSUCH_ITEM];
      ## an unknown non-hashref $item is also a DB_ERR:
      default { "RPL_DB_ERR" }
    }
    return rplprintf( $core->lang->{$rpl},
      { 
        nick  => $msg_h->{src_nick}//'',
        rdb   => $rdb, 
        index => $selection 
      }
    );
  }

  my $content = $item->{String} // '(undef - broken db!)';
  my $itemkey = $item->{DBKEY}  // '(undef - broken db!)';
  
  return "[${itemkey}] $content";
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
  ## FIXME handle voting here ... ?
  ## this got out of hand fast.
  ## really needs to be dispatched out, badly.
  my ($self, $parsed_msg_a, $msg_h) = @_;
  my $core = $self->{core};
  my @message = @{ $parsed_msg_a };
  my @handled = qw/
    add
    del
    dbadd
    dbdel
    info
    search
    searchidx
  /;

  my $cmd = lc(shift @message || '');
  $cmd = 'del' if $cmd eq 'delete';

  unless ($cmd && $cmd ~~ @handled) {
    return "Commands: add <rdb>, del <rdb>, info <rdb> <idx>, "
           ."get <rdb> <idx>, search(idx) <rdb> <str>, dbadd <rdb>, "
           ."dbdel <rdb>";
  }
  
  my $pcfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $required_levs = $pcfg->{RequiredLevels} // {};
  my %access_levs = (
    info   => $required_levs->{rdb_info}      // 0,
    dbadd  => $required_levs->{rdb_create}    // 9999,
    dbdel  => $required_levs->{rdb_delete}    // 9999,
    add    => $required_levs->{rdb_add_item}  // 2,
    del    => $required_levs->{rdb_del_item}  // 3,
    search    => $required_levs->{rdb_search} // 0,
    searchidx => $required_levs->{rdb_search} // 0,
  );
  
  my $context  = $msg_h->{context};
  my $nickname = $msg_h->{src_nick};
  my $user_lev = $core->auth_level($context, $nickname);
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
      
      return 'RDB name must be in the A-Za-z0-9 set'
        unless $rdb =~ /^[A-Za-z0-9]+$/;

      my $retval = $dbmgr->createdb($rdb);
      if      ($retval == RDB_EXISTS) {
        $resp = rplprintf( $core->lang->{RDB_ERR_RDB_EXISTS},
          { nick => $nickname, rdb => $rdb, op => $cmd }
        );
      } elsif ($retval == RDB_DBFAIL) {
        $resp = rplprintf( $core->lang->{RPL_DB_ERR} );
      } elsif ($retval == SUCCESS) {
        $resp = rplprintf( $core->lang->{RDB_CREATED},
          { nick => $nickname, rdb  => $rdb }
        );
      } else {
        $resp = 'Unknown retval from createdb?';
      }
    }

    when ("dbdel") {
      ## delete a rdb if we're allowed (per conf and requiredlev)
      my ($rdb) = @message;
      return 'Syntax: rdb dbdel <RDB>' unless $rdb;
      my $retval = $self->_delete_rdb($rdb);

      SWITCH: {
        if ($retval == RDB_NOTPERMITTED) {
          $resp = rplprintf( $core->lang->{RDB_ERR_NOTPERMITTED},
            { nick => $nickname, rdb => $rdb, op => $cmd }
          );
          last SWITCH
        }

        if ($retval == RDB_NOSUCH) {
          $resp = rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB},
            { nick => $nickname, rdb => $rdb }
          );
          last SWITCH
        }
        
        if ($retval == RDB_DBFAIL) {
          $resp = rplprintf( $core->lang->{RPL_DB_ERR} );
          last SWITCH
        }
        
        if ($retval == RDB_FILEFAILURE) {
          $resp = rplprintf( $core->lang->{RDB_UNLINK_FAILED},
            { nick => $nickname, rdb => $rdb }
          );
          last SWITCH
        }

        if ($retval == SUCCESS) {
          $resp = rplprintf( $core->lang->{RDB_DELETED},
            { nick => $nickname, rdb => $rdb }
          );
          last SWITCH
        }

        $resp = 'Unknown retval from _delete_rdb?';
      }
      
    }
    
    when ("add") {
      my ($rdb, $item) = @message;
      return 'Syntax: rdb add <RDB> <item>' unless $rdb and $item;
      my $retval = $self->_add_item($rdb, decode_irc($item), $username);
      if      ($retval ~~ RDB_NOSUCH) {
        $resp = rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB},
          { nick => $nickname, rdb => $rdb }
        );
      } elsif ($retval ~~ RDB_DBFAIL) {
        $resp = rplprintf( $core->lang->{RPL_DB_ERR} );
      } else {
        ## should've been returned a unique index number
        $resp = rplprintf( $core->lang->{RDB_ITEM_ADDED},
          { nick => $nickname, rdb => $rdb, index => $retval }
        );
      }
    }
    
    when ("del") {
      my ($rdb, $item_idx) = @message;
      return 'Syntax: rdb del <RDB> <index number>'
        unless $rdb and $item_idx;
      my $retval = $self->_delete_item($rdb, $item_idx, $username);
      SWITCH: {
        if ($retval ~~ RDB_NOSUCH) {
          $resp = rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB},
            { nick => $nickname, rdb  => $rdb }
          );
          last SWITCH
        }
        
        if ($retval ~~ RDB_DBFAIL) {
          $resp = rplprintf( $core->lang->{RPL_DB_ERR} );
          last SWITCH
        }
        
        if ($retval ~~ RDB_NOSUCH_ITEM) {
          $resp = rplprintf( $core->lang->{RDB_ERR_NO_SUCH_ITEM},
            { nick => $nickname, rdb => $rdb, index => $item_idx }
          );
          last SWITCH
        }
        
        $resp = rplprintf( $core->lang->{RDB_ITEM_DELETED},
            { nick => $nickname, rdb => $rdb, index => $item_idx }
        );
      }  ## SWITCH
    }

    when ("get") {
      my ($rdb, $idx) = @message;
      return 'Syntax: rdb get <RDB> <index key>'
        unless $rdb;
      
      my $dbmgr = $self->{CDBM};
      unless ( $dbmgr->dbexists($rdb) ) {
        return rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB},
          { nick => $nickname, rdb => $rdb }
        );
      }
      
      my $item = $dbmgr->get($rdb, $idx);
      unless (ref $item eq 'HASH') {
        if    ($item ~~ RDB_NOSUCH_ITEM) {
          return rplprintf( $core->lang->{RDB_ERR_NO_SUCH_ITEM},
            { nick => $nickname, rdb  => $rdb, index => $idx }
          );
        }
        elsif ($item ~~ RDB_DBFAIL) {
          return rplprintf( $core->lang->{RPL_DB_ERR} );
        }
        elsif ($item ~~ RDB_NOSUCH) {
          return rplprintf( $core->lang->{RPL_ERR_NO_SUCH_RDB},
            { nick => $nickname, rdb => $rdb }
          );
        }
        return "Unknown exit status $item"      
      }
     
      my $indexkey = $item->{DBKEY}  // '(undef - broken db!)';
      my $content  = $item->{String} // '(undef - broken db!)';
      $resp = "[${indexkey}] $content"
    }

    when ("info") {
      ## return metadata about an item by rdb and index number
      my ($rdb, $idx) = @message;
      return 'Syntax: rdb info <RDB> <index key>'
        unless $rdb;
      
      my $dbmgr = $self->{CDBM};
      unless ( $dbmgr->dbexists($rdb) ) {
        return rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB},
          { nick => $nickname, rdb  => $rdb  }
        );
      }

      unless ($idx) {
        my $n_keys = $dbmgr->get_keys($rdb);
        return "RDB $rdb has $n_keys items"
      }

      my $item = $dbmgr->get($rdb, $idx);
      unless (ref $item eq 'HASH') {
      
        if    ($item ~~ RDB_NOSUCH_ITEM) {
          return rplprintf( $core->lang->{RDB_ERR_NO_SUCH_ITEM},
            { nick => $nickname, rdb  => $rdb, index => $idx }
          );
        }
        elsif ($item ~~ RDB_DBFAIL) {
          return rplprintf( $core->lang->{RPL_DB_ERR} );
        }
        elsif ($item ~~ RDB_NOSUCH) {
          return rplprintf( $core->lang->{RPL_ERR_NO_SUCH_RDB},
            { nick => $nickname, rdb => $rdb }
          );
        }
        return "Unknown exit status $item"
      }

      my $added_dt = DateTime->from_epoch(
        epoch => $item->{AddedAt} // 0
      );
      my $votes_r = $item->{Votes} // {};
      my $added_by = $item->{AddedBy} // '(undef)';
  
      my $rplvars = {
        nick  => $nickname,
        rdb   => $rdb,
        index => $idx,
        date  => $added_dt->date,
        time  => $added_dt->time,
        addedby => $added_by,
        votedup   => $votes_r->{Up} // 0,
        voteddown => $votes_r->{Down} // 0,
      };

      $resp = rplprintf( $core->lang->{RDB_ITEM_INFO}, $rplvars );
    }

    when ("search") {
      ## search by rdb and string
      ## parse, call _cmd_randq and just pass off to that
      my ($rdb, $str) = @message;
      $str = '*' unless $str;
      return 'Syntax: rdb search <RDB> <string>' unless $rdb;

      $resp = $self->_cmd_randq([], $msg_h, 'rdb', $rdb, $str)
    }
    
    when ("searchidx") {
      my ($rdb, $str) = @message;
      return 'Syntax: rdb searchidx <RDB> <string>' 
        unless $rdb and $str;
      my @indices = $self->_searchidx($rdb, $str);
      $indices[0] = "NONE" unless @indices;
      $resp = "First 20 matches: ".join('  ', @indices);
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
  my $rdb     = ${$_[3] // \'main'};
  my $orig    = ${$_[4] // \$rdb };

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
  
  ## construct fake msg hash for _select_random
  my $msg_h = { };
  $msg_h->{src_nick} = $nick;
  $msg_h->{channel}  = $channel;
  
  my $random = $send_orig ? $orig 
               : $self->_select_random($msg_h, $rdb, 'quietfail') ;

  $core->send_event( 
    'info3_relay_string', $context, $channel, $nick, $random 
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
    next SERVER unless $core->Servers->{$context}->{Connected};
    my $irc = $core->Servers->{$context}->{Object} || next SERVER;
    my $chcfg = $core->get_channels_cfg($context);

    $core->log->debug("rdb_broadcast to $context");

    my $on_channels = $irc->channels || {};
    my $casemap = $core->Servers->{$context}->{CaseMap} // 'rfc1459';
    my @channels = map { lc_irc($_, $casemap) } keys %$on_channels;

    CHAN: for my $channel (@channels) {
      next CHAN if $chcfg->{$channel}->{rdb_randstuffs} == 0;
 
      ## action/msg check    
      if ( index($random, '+') == 0 ) {
        $random = substr($random, 1);
        $core->log->debug(
          "rdb_broadcast (action) -> $context -> $channel"
        );
        $core->send_event( 'send_action', $context, $channel, $random );
      } else {
        $core->log->debug("rdb_broadcast -> $context -> $channel");
        $core->send_event( 'send_message', $context, $channel, $random );
      }
 
    } # CHAN
  } # SERVER

  ## reset timer unless randdelay is 0
  if ($self->{RandDelay}) {
    $core->timer_set( $self->{RandDelay}, 
      { Event => 'rdb_broadcast' }, 'RANDSTUFF'
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
    $self->{core}->log->warn("searchidx failure: retval: $ret");
    return wantarray ? () : $ret ;
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
    return RDB_NOSUCH
  }
  
  my $itemref = {
    AddedBy => $username,
    AddedAt => time,
    String => $item,
    Votes => { Up => 0, Down => 0 },
  };

  ## on failure put() will return one of:
  ##   RDB_NOSUCH
  ##   RDB_DBFAIL
  my $status = $dbmgr->put($rdb, $itemref);
  
  if ($status =~ /^\d+$/) {
    return $status if $status == RDB_DBFAIL 
                   or $status == RDB_NOSUCH;
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
    return RDB_NOSUCH
  }

  my $retval = $dbmgr->del($rdb, $item_idx);
  if ( $retval 
       ~~ [ RDB_DBFAIL, RDB_NOSUCH, RDB_NOSUCH_ITEM ] ) 
  {
    $core->log->debug(
      "cannot delete item: $item_idx [$rdb] (err: $retval)"
    );
    return $retval
  }

  --$core->Provided->{randstuff_items} if $rdb eq 'main';
  return $item_idx
}


sub _delete_rdb {
  my ($self, $rdb) = @_;
  return unless $rdb;
  my $core = $self->{core};
  my $pcfg = $core->get_plugin_cfg( __PACKAGE__ );

  my $can_delete = $pcfg->{Opts}->{AllowDelete} // 0;

  unless ($can_delete) {
    $core->log->debug("attempted delete but AllowDelete = 0");
    return RDB_NOTPERMITTED
  }

  my $dbmgr = $self->{CDBM};

  unless ( $dbmgr->dbexists($rdb) ) {
    $core->log->debug("cannot delete nonexistant rdb $rdb");
    return RDB_NOSUCH
  } else {
    if ($rdb eq 'main') {
      ## check if this is 'main'
      ##  check core cfg to see if we can delete 'main'
      ##  default to no
      my $can_del_main = $pcfg->{Opts}->{AllowDeleteMain} // 0;
      unless ($can_del_main) {
        $core->log->debug(
          "attempted to delete main but AllowDelete Main = 0"
        );
        return RDB_NOTPERMITTED
      }
    }
    
    return $dbmgr->deldb($rdb);
  }
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
in the [A-Za-z0-9] set.

=head1 COMMANDS

Commands are prefixed with the bot's nickname, rather than CmdChar.

This is a holdover from darkbot legacy syntax.

  <JoeUser> botnick: randq some*glob

=head2 random

Retrieves a single random response ('randstuff') from the "main" RDB.


=head2 randq

Search for a specified glob in RDB 'main' (randstuffs):

  <JoeUser> bot: randq some+string*

See L<Cobalt::Utils/glob_to_re_str> for details regarding glob syntax.


=head2 randstuff

Add a new "randstuff" to the 'main' RDB

  <JoeUser> bot: randstuff new randstuff string


=head2 rdb

=head3 rdb info

=head3 rdb add

=head3 rdb del

=head3 rdb dbadd

=head3 rdb dbdel

=head3 rdb search

=head3 rdb searchidx

=head1 EVENTS

=head2 Received events

=head2 Emitted events

=cut
