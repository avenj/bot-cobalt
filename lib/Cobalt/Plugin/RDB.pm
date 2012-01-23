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
  RDB_WRITEFAIL => 3,  
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

  my $db = $self->_read_db || { main => { } };
  $self->{RDB} = $db;

  ## kickstart a randstuff timer (named timer for rdb_broadcast)
  ## delay is in Opts->RandDelay as a timestr
  ## (0 turns off timer)
  my $cfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $randdelay = $cfg->{Opts}->{RandDelay} // '30m';

  $randdelay = timestr_to_secs($randdelay)
    unless ($randdelay =~ /^\d+$/);

  $self->{RandDelay} = $randdelay;
  if ($randdelay) {
    $core->timer_set( $randdelay,
        {
          Event => 'rdb_broadcast',
          Args => [ ],
        },
      'RANDSTUFF'
    );
  }

  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  $core->log->info("Unregistering core IRC plugin");
  return PLUGIN_EAT_NONE
}


sub Bot_public_msg {
  my ($self, $core) = @_;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};
  my @handled = qw/
    randstuff
    randq
    rdb    
  /;

  ## would be better in a public_cmd_, but eh, darkbot legacy syntax..
  return PLUGIN_EAT_NONE unless $msg->{highlight};
  ## since this is a highlighted message, bot's nickname is first:
  shift @message;
  my $cmd = lc(shift @message || '');
  ## ..if it's not @handled we don't care:
  return PLUGIN_EAT_NONE unless $cmd and $cmd ~~ @handled;

  my $resp;

  given ($cmd) {
    $resp = $self->_cmd_randstuff(\@message, $msg)
      when "randstuff";
    $resp = $self->_cmd_randq(\@message, $msg)
      when "randq";
    $resp = $self->_cmd_rdb(\@message, $msg)
      when "rdb";
  }

  ## darkbotalike except w/ 'rdb add/del/search/info' commands
  ## support oldschool ~rdb syntax
  ## prepend index numbers on searched randqs
  ## turn AddedAt into a date in 'info'

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
  
  my $rdb = 'main';      # default to 'main'

  ## this may be randstuff ~rdb ... syntax:
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
  my ($self, $parsed_msg_a, $msg_h) = @_;

  ## FIXME call a search against 'main'
  ## return a random result from @matches
  ## try to skip dupes if possible?

}

sub _cmd_rdb {
  my ($self, $parsed_msg_a, $msg_h) = @_;
  my @message = @{ $parsed_msg_a };
  my @handled = qw/
    add
    del
    delete
    info
    search
  /;

  my $cmd = lc(shift @message || '');

  unless ($cmd and $cmd ~~ @handled) {
    return "Valid commands: add <rdb>, del <rdb>, info <rdb> <idx>, "
           ."search <rdb> <str>";
  }

  ## FIXME

}


  ### self-events ###

sub Bot_rdb_triggered {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $channel = ${$_[1]};
  my $rdb = ${$_[2]} // 'main';

  my $random_string = $self->_get_random($rdb);
    
  ## FIXME event normally triggered by Info3 when a topic references a ~rdb
  ## grab a random response and throw it back at the pipeline for info plugin to pick up and do variable replacement on
  ## send_event('info3_relay_string', context, chan, str) or something similar?
}

sub Bot_rdb_broadcast {
  my ($self, $core) = splice @_, 0, 2;
  ## our timer self-event
  ## grab all channels for all contexts
  ## throw a randstuff at them unless told not to in channels conf

  ## reset timer unless randdelay is 0
  if ($self->{RandDelay}) {
    $core->timer_set( $self->{RandDelay},
        {
          Event => 'rdb_broadcast',
          Args => [ ],
        },
      'RANDSTUFF'
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

  my $re = glob_to_re($string);

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

  my @indexes = sort {$a<=>$b} keys %{ $self->{RDB} };
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

  ## item indexes are permanent
  ## delete (and later return) the old item
  ## replace the index with a deletion marker
  ## FIXME - an optional timed purge mechanism that reshuffles indexes?
  my $old_item = delete $self->{RDB}->{$rdb}->{$item_idx};
  $self->{RDB}->{$rdb}->{$item_idx} = {
    DeletedAt => time,
    DeletedBy => $username || 'Unknown' ;
  }  
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
    return RDB_WRITEFAIL
  }
}


1;
