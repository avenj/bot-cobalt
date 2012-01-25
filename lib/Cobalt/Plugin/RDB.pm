package Cobalt::Plugin::RDB;
our $VERSION = '0.10';

## Act a bit like darkbot/cobalt1 randstuff & RDBs
##
## $self->{RDB}->{$rdb} = {
##   String => "string",
##   AddedAt => time(),
##   AddedBy => $username, # or 'Importer'
##   Votes => {
##     Up   => 0,
##     Down => 0,
##   },
## }

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use Cobalt::Serializer;

use Cobalt::Utils qw/ :ALL /;

use constant {
  SUCCESS => 1,

  RDB_EXISTS    => 2,
#  RDB_WRITEFAIL => 3,  

  RDB_NOSUCH => 4,
  RDB_NOSUCH_ITEM => 5,

  RDB_ALREADY_DELETED => 6,

  RDB_NOTPERMITTED => 7,
};


sub new { bless( {}, shift ) }

sub Cobalt_register {
  my ($self, $core) = @_;
  $self->{core} = $core;
  $core->plugin_register($self, 'SERVER',
    [ 
      'public_msg',
      'rdb_broadcast',
      'rdb_triggered',
    ],
  );  

  ## Read in serialized rdb
  my $db = $self->_read_db || { main => { } };
  $self->{RDB} = $db;

  ## kickstart a randstuff timer (named timer for rdb_broadcast)
  ## delay is in Opts->RandDelay as a timestr
  ## (0 turns off timer)
  my $cfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $randdelay = $cfg->{Opts}->{RandDelay} // '30m';

  $randdelay = timestr_to_secs($randdelay) unless $randdelay =~ /^\d+$/;

  $self->{RandDelay} = $randdelay;
  if ($randdelay) {
    $core->timer_set( $randdelay, 
      { Event => 'rdb_broadcast' }, 'RANDSTUFF'
    );
  }

  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  $core->log->info("Unregistering random stuff");
  return PLUGIN_EAT_NONE
}


sub Bot_public_msg {
  my ($self, $core) = @_;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};
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
  my $channel = $msg->{channel};
  $core->send_event( 'send_message', $context, $channel, $resp )
    if $resp;

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
    $rdb = shift @message;
    unless ($rdb && exists $self->{RDB}->{$rdb}) {
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

  unless ($randstuff_str) {
    return rplprintf( $core->lang->{RDB_ERR_NO_STRING},
      {
        nick => $src_nick,
        rdb  => $rdb,
      }
    );
  }

  ## call _add_item
  my $username = $core->auth_username($context, $src_nick);
  my $newidx = $self->_add_item($rdb, $randstuff_str, $username);

  ## return success RPL w/ newidx
  return "Unknown failure, no index returned" unless $newidx;
  return rplprintf( $core->lang->{RDB_ITEM_ADDED},
    {
      nick  => $src_nick,
      rdb   => $rdb,
      index => $newidx,
    }
  );
}

sub _cmd_randq {
  my ($self, $parsed_msg_a, $msg_h, $type, $rdbpassed, $strpassed) = @_;

  ## also handler for 'rdb search rdb str'

  my @message = @{ $parsed_msg_a };
  my($str, $rdb);
  if    ($type eq 'random') {
    $rdb = 'main';
    $str = '*';
  } elsif ($type eq 'rdb') {
    $rdb = $rdbpassed;
    $str = $strpassed;
  } else {
    $str = shift @message || '<*>';
  }

  ## get an array of matching indexes for rdb 'main':
  my @matches = $self->_search($str, $rdb);
  my $selection = @matches ? 
                   $matches[rand@matches] 
                   : return 'No match' ;
  if ($self->{LastRandq} eq $selection && @matches > 1) {
    ## we probably just spit this randq out
    ## give it one more shot
    $selection = $matches[rand@matches];
  }
  $self->{LastRandq} = $selection;

  my $rs_ref = $self->{RDB}->{$rdb}->{$selection};
  unless (defined $rs_ref->{String}) {
    return "Undefined String in rdb $rdb item $selection"
  }

  my $resp = defined $rs_ref->{String} ?
             $rs_ref->{String}
             : return "Undefined String in rdb $rdb item $selection" ;
  return "[${selection}] ${resp}";
}

sub _cmd_rdb {
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
    return "Valid commands: add <rdb>, del <rdb>, info <rdb> <idx>, "
           ."search <rdb> <str>";
  }
  
  my $pcfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $required_levs = $pcfg->{RequiredLevels} // {};
  my %access_levs = (
    info   => $required_levs->{rdb_info} // 0,
    dbadd  => $required_levs->{rdb_create} // 9999,
    dbdel  => $required_levs->{rdb_delete} // 9999,
    add    => $required_levs->{rdb_add_item} // 2,
    del    => $required_levs->{rdb_del_item} // 3,
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

  my $resp;
  given ($cmd) {

    when ("dbadd") {
      ## _create a new rdb if it doesn't exist
      my ($rdb) = @message;
      return 'Syntax: rdb dbadd <RDB>' unless $rdb;
      my $retval = $self->_create_rdb($rdb);      
      if      ($retval eq RDB_EXISTS) {
        $resp = rplprintf( $core->lang->{RDB_ERR_RDB_EXISTS},
          {
            nick => $nickname,
            rdb  => $rdb,
            op   => $cmd,
          }
        );
      } elsif ($retval eq SUCCESS) {
        $resp = rplprintf( $core->lang->{RDB_CREATED},
          {
            nick => $nickname,
            rdb  => $rdb
          }
        );
      } else {
        $resp = 'Unknown retval from _create_rdb?';
      }
    }

    when ("dbdel") {
      ## delete a rdb if we're allowed (per conf and requiredlev)
      my ($rdb) = @message;
      return 'Syntax: rdb dbdel <RDB>' unless $rdb;
      my $retval = $self->_delete_rdb($rdb);

      SWITCH: {
        if ($retval eq RDB_NOTPERMITTED) {
          $resp = rplprintf( $core->lang->{RDB_ERR_NOTPERMITTED},
            {
              nick => $nickname,
              rdb  => $rdb,
              op   => $cmd,
            }
          );
          last SWITCH
        }
        if ($retval eq RDB_NOSUCH) {
          $resp = rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB},
            {
              nick => $nickname,
              rdb  => $rdb,
            }
          );
          last SWITCH
        }
        if ($retval eq SUCCESS) {
          $resp = rplprintf( $core->lang->{RDB_DELETED},
            {
              nick => $nickname,
              rdb  => $rdb,
            }
          );
          last SWITCH
        }
        $resp = 'Unknown retval from _delete_rdb?';
      }
      
    }
    
    ## FIXME access levels for add/del
    when ("add") {
      my ($rdb, $item) = @message;
      return 'Syntax: rdb add <RDB> <item>' unless $rdb and $item;
      my $retval = $self->_add_item($rdb, $item, $username);
      if ($retval eq RDB_NOSUCH) {
        $resp = rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB},
          {
            nick => $nickname,
            rdb  => $rdb,
          }
        );
      } else {
        ## should've been returned a unique index number
        $resp = rplprintf( $core->lang->{RDB_ITEM_ADDED},
          {
            nick => $nickname,
            rdb  => $rdb,
            index => $retval,
          }
        );
      }
    }
    
    when ("del") {
      my ($rdb, $item_idx) = @message;
      return 'Syntax: rdb del <RDB> <index number>'
        unless $rdb and $item_idx;
      my $retval = $self->_delete_item($rdb, $item_idx, $username);
      if      ($retval eq RDB_NOSUCH) {
        $resp = rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB},
          {
            nick => $nickname,
            rdb  => $rdb,
          }
        );
      } elsif ($retval eq RDB_NOSUCH_ITEM) {
        $resp = rplprintf( $core->lang->{RDB_ERR_NO_SUCH_ITEM},
          {
            nick => $nickname,
            rdb  => $rdb,
            index => $item_idx,
          }
        );
      } elsif ($retval eq RDB_ALREADY_DELETED) {
        $resp = rplprintf( $core->lang->{RDB_ERR_ITEM_DELETED},
          {
            nick => $nickname,
            rdb  => $rdb,
            index => $item_idx,
          }
        );
      } else {
        ## should've gotten old item hash back
        $resp = rplprintf( $core->lang->{RDB_ITEM_DELETED},
          {
            nick => $nickname,
            rdb  => $rdb,
            index => $item_idx,
          }
        );
      }
    }

    when ("info") {
      ## return metadata about an item by rdb and index number
      my ($rdb, $idx) = @message;
      return 'Syntax: rdb info <RDB> <index number>'
        unless $rdb and $idx;
      unless (exists $self->{RDB}->{$rdb}) {
        return rplprintf( $core->lang->{RDB_ERR_NO_SUCH_RDB},
          {
            nick => $nickname,
            rdb  => $rdb,
          }
        );
      }

      unless (exists $self->{RDB}->{$rdb}->{$idx}) {
        return rplprintf( $core->lang->{RDB_ERR_NO_SUCH_ITEM},
          {
            nick => $nickname,
            rdb  => $rdb,
            index => $idx,
          }
        );
      }
        
      if (defined $self->{RDB}->{$rdb}->{$idx}->{DeletedAt}) {
        return rplprintf( $core->lang->{RDB_ERR_ITEM_DELETED},
          {
            nick => $nickname,
            rdb  => $rdb,
            index => $idx,
          }
        );
      }
      
      ## FIXME grab info and send RPL

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
      my @indexes = $self->_search($str, $rdb);
      $indexes[0] = "NONE" unless @indexes;
      $resp = "First 20 matches: ".join('  ', @indexes);
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
  my $rdb     = ${$_[3]} // 'main';

  ## event normally triggered by Info3 when a topic references a ~rdb
  ## grab a random response and throw it back at the pipeline
  ## info3 plugin can pick it up and do variable replacement on it 

  my $random = $self->_get_random($rdb);

  $self->send_event( 
    'info3_relay_string', $context, $channel, $nick, $random 
  );

  return PLUGIN_EAT_ALL
}

sub Bot_rdb_broadcast {
  my ($self, $core) = splice @_, 0, 2;
  ## our timer self-event

  my $random = $self->_get_random;
  
  ## iterate channels cfg
  ## throw randstuffs at configured channels unless told not to
  my $servers = $core->Servers;
  for my $context (keys %$servers) {
    next unless $core->Servers->{$context}->{Connected};
    my $irc = $core->Servers->{$context}->{Object} // next;
    my $chcfg = $core->get_channels_cfg($context);

    for my $channel (keys %$chcfg) {
      $core->send_event( 'send_message', $context, $channel, $random ) 
        if $chcfg->{$channel}->{rdb_randstuffs}
        and $irc->is_channel_synced($channel) ;
    }

  }

  ## reset timer unless randdelay is 0
  if ($self->{RandDelay}) {
    $core->timer_set( $self->{RandDelay}, 
      { Event => 'rdb_broadcast' }, 'RANDSTUFF'
    );
  }

  return PLUGIN_EAT_ALL  ## theoretically no one else cares
}


  ### 'worker' methods ###

sub _get_random {
  ## get non-deleted random stuff from specified rdb
  ## returns the hashref
  my ($self, $rdb) = @_;
  $rdb = 'main' unless $rdb;
  my $rdbref = $self->{RDB}->{$rdb} // {};
  my $entries_c = scalar keys %$rdbref;
  my($rand_idx, $pos);
  do {
    ++$pos;
    ## skip deleted
    $rand_idx = int rand $entries_c;
  } until (defined $rdbref->{$rand_idx}->{String} || $pos == $entries_c);
  return $rdbref->{$rand_idx};
}

sub _search {
  my ($self, $string, $rdb) = @_;
  $string = '<*>' unless $string;
  $rdb   = 'main' unless $rdb;

  my $re_str = glob_to_re_str($string);
  ## case-insensitive:
  my $re = qr/$re_str/i;

  my @matches;
  for my $randq_idx (keys $self->{RDB}->{$rdb}) {
    my $content = $self->{RDB}->{$rdb}->{$randq_idx}->{String};
    push(@matches, $randq_idx) if $content =~ $re;
  }

  ## returns array or arrayref of INDEXES for matching randqs

  wantarray ? return @matches : return \@matches ;
}

sub _add_item {
  my ($self, $rdb, $item, $username) = @_;
  return unless $rdb and defined $item;
  my $core = $self->{core};
  $username = '-undefined' unless $username;
  
  unless (exists $self->{RDB}->{$rdb}) {
    $core->log->debug("cannot add item to nonexistant rdb: $rdb");
    return RDB_NOSUCH
  }

  my @indexes = sort {$a<=>$b} keys %{ $self->{RDB}->{$rdb} };
  @indexes = ('0') unless @indexes;
  my $index = (pop @indexes) + 1;

  $self->{RDB}->{$rdb}->{$index} = {
    AddedBy => $username,
    AddedAt => time,
    String => $item,
    Votes => { Up => 0, Down => 0 },
  };

  $self->_write_db;
  ## Returns new index number
  return $index
}

sub _delete_item {
  my ($self, $rdb, $item_idx, $username) = @_;
  return unless $rdb and defined $item_idx;
  my $core = $self->{core};

  unless (exists $self->{RDB}->{$rdb}) {
    $core->log->debug("cannot delete from nonexistant rdb: $rdb");
    return RDB_NOSUCH
  }

  unless (exists $self->{RDB}->{$rdb}->{$item_idx}) {
    $core->log->debug("cannot delete nonexistant item: $item_idx [$rdb]");
    return RDB_NOSUCH_ITEM
  }

  if (defined $self->{RDB}->{$rdb}->{$item_idx}->{DeletedAt}) {
    $core->log->debug("item $item_idx in rdb $rdb already marked deleted");
    return RDB_ALREADY_DELETED
  }

  ## item indexes are permanent
  ## delete (and later return) the old item
  ## replace the index with a deletion marker
  ## FIXME - an optional timed purge mechanism that reshuffles indexes?
  my $old_item = delete $self->{RDB}->{$rdb}->{$item_idx};
  $self->{RDB}->{$rdb}->{$item_idx} = {
    DeletedAt => time,
    DeletedBy => $username || 'Unknown',
  };
  $self->_write_db;
  return $old_item
}

sub _create_rdb {
  my ($self, $rdb) = @_;
  return unless $rdb;
  my $core = $self->{core};

  if (exists $self->{RDB}->{$rdb}) {
    $core->log->debug("cannot create preexisting rdb: $rdb");
    return RDB_EXISTS
  } else {
    $self->{RDB}->{$rdb} = { };
    $self->_write_db;
    return SUCCESS
  }
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

  unless (exists $self->{RDB}->{$rdb}) {
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
    delete $self->{RDB}->{$rdb};
    return SUCCESS
  }
}


  ### on-disk db ###

sub _read_db {
  my ($self) = @_;
  my $core = $self->{core};
  my $cfg = $core->get_plugin_cfg( __PACKAGE__ );

  my $serializer = Cobalt::Serializer->new;

  my $var = $core->var;
  my $relative_to_var = $cfg->{Opts}->{RandDB};
  my $db_path = $var ."/". $relative_to_var;

  my $db = $serializer->readfile( $db_path );

  if ($db && ref $db eq 'HASH') {
    return $db
  } else {
    $core->log->warn("Could not read RDB, creating an empty one...");
    return
  }  
}

sub _write_db {
  my ($self) = @_;
  my $core = $self->{core};
  my $cfg = $core->get_plugin_cfg( __PACKAGE__ );

  my $serializer = Cobalt::Serializer->new;

  my $var = $core->var;
  my $relative_to_var = $cfg->{Opts}->{RandDB};
  my $db_path = $var ."/". $relative_to_var;
  my $ref = $self->{RDB};
  if ( $serializer->writefile( $db_path, $ref ) ) {
    return SUCCESS
  } else {
    $core->log->warn("Serializer failure, could not write RDB");
    return
  }
}


1;
