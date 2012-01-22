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

use Cobalt::Utils qw/ rplprintf timestr_to_secs /;

use constant {
  SUCCESS => 1,
  RDB_EXISTS    => 2,
  RDB_WRITEFAIL => 3,  
  RDB_READFAIL  => 4,
};


sub new { bless( {}, shift ) }

sub Cobalt_register {
  my ($self, $core) = @_;
  $self->{core} = $core;
  $core->plugin_register($self, 'SERVER',
    [ 
      'public_msg',
      'rdb_broadcast',
    ],
  );  

  eval "require Text::Glob";
  if ($@) {
    $self->{SearchEnabled} = 0;
    $core->log->warn("You don't seem to have Text::Glob!");
    $core->log->warn("Searching RDBs will be disabled.");
  } else {
    no warnings;
    $Text::Glob::strict_leading_dot = 0;
    $Text::Glob::strict_wildcard_slash = 0;
    use warnings;
    Text::Glob->import(qw/glob_to_regex glob_to_regex_string/);
    $self->{SearchEnabled} = 1;
  }

  ## kickstart a randstuff timer (named timer for rdb_broadcast)
  ## delay is in Opts->RandDelay as a timestr
  my $cfg = $core->get_plugin_cfg( __PACKAGE__ );
  my $randdelay = $cfg->{Opts}->{RandDelay} // '30m';
  ## 0 turns off timer
  $randdelay = timestr_to_secs($randdelay) unless $randdelay == 0;
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
  ## FIXME db sync?
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

  ## if this is a highlighted message, bot's nickname is first:
  shift @message if $msg->{highlight};
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

  ## FIXME authcheck

  my $rdb = 'main';      # default to 'main'

  ## this may be randstuff ~rdb ... syntax:
  if (index($message[0], '~') == 0) {
    $rdb = shift @message;
    unless (exists $self->{RDB}->{$rdb}) {
      ## FIXME return rdb doesn't exist RPL
    }
  }

  ## should have just the randstuff itself now:
  my $randstuff_str = join ' ', @message;

  ## FIXME call _add_item

}

sub _cmd_randq {
  my ($self, $parsed_msg_a, $msg_h) = @_;

  ## FIXME call a search

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

sub Bot_rdb_broadcast {
  my ($self, $core) = splice @_, 0, 2;
  ## FIXME
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

}


  ### 'worker' methods ###

sub _search {
  my ($self, $string, $rdb) = @_;
  return "Search disabled, no Text::Glob found" 
    unless $self->{SearchEnabled};
  $string = '<*>' unless $string;
  my $re = glob_to_regex($string);

  $rdb = 'main' unless $rdb;

  my @matches;
  for my $randq_idx (keys $self->{RDB}->{$rdb}) {
    my $content = $self->{RDB}->{$rdb}->{$randq_idx}->{String};
    push(@matches, $randq_idx) if $content =~ m/$re/;
  }

  ## returns array of INDEXES for matching randqs in this rdb

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
}

sub _delete_item {
  my ($self, $rdb, $item_idx) = @_;
  return unless $rdb and defined $item_idx;
  my $core = $self->{core};
  return delete $self->{RDB}->{$rdb}->{$item_idx};
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

  if ( $serializer->readfile( $db_path ) ) {
    return SUCCESS
  } else {
    $core->log->warn("Serializer failure, could not read RDB");
    return RDB_READFAIL
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
