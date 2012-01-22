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

use constant {
  SUCCESS => 1,
  RDB_EXISTS    => 2,
  RDB_WRITEFAIL => 3,  
};


sub new { bless( {}, shift ) }

sub Cobalt_register {
  my ($self, $core) = @_;

  $core->plugin_register($self, 'SERVER',
    [ 'public_msg' ],
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

  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  $core->log->info("Unregistering core IRC plugin");
  ## FIXME db sync?
  return PLUGIN_EAT_NONE
}


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
