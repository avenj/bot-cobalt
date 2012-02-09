package Cobalt::Plugin::RDB::Database;
our $VERSION = '0.26';

use 5.12.1;
use strict;
use warnings;
use Carp;

use Cobalt::DB;

use Cobalt::Plugin::RDB::Constants;
use Cobalt::Plugin::RDB::SearchCache;

use Cobalt::Utils qw/ glob_to_re_str /;

use Cwd qw/ abs_path /;

use Digest::SHA1 qw/sha1_hex/;

use File::Basename qw/fileparse/;
use File::Find;
use File::Path qw/mkpath/;

use Time::HiRes;


sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;

  my %opts = @_;
  
  unless ( ref $opts{core} ) {
    croak "new() needs a core => parameter"
  }  
  my $core = $opts{core};
  $self->{core} = $core;

  my $rdbdir = $opts{RDBDir};  
  $self->{RDBDir} = $rdbdir;
  unless ( $self->{RDBDir} ) {
    croak "new() needs a RDBDir parameter"
  }
  
  $self->{RDBPaths} = {};
  
  $self->{CacheObj} = Cobalt::Plugin::RDB::SearchCache->new(
    MaxKeys => $opts{CacheKeys} // 30,
  );
  
  $core->log->debug("Using RDBDir $rdbdir");
  
  unless (-e $rdbdir) {
    $core->log->debug("Did not find RDBDir $rdbdir, attempting mkpath");
    mkpath($rdbdir);
  }
  
  unless (-d $rdbdir) {
    $core->log->error("$rdbdir not a directory");
    return
  }
  
  my @paths;
  find(sub {
#      return if $File::Find::name ~~ @paths;
      push(@paths, $File::Find::name) if $_ =~ /\.rdb$/;
    },
    $rdbdir
  );
  
  for my $path (@paths) {
    my $rdb_name = fileparse($path, '.rdb');
    $core->log->debug("$rdb_name -> $path");
    
    $self->{RDBPaths}->{$rdb_name} = $path;
  }
  
  unless ( $self->{RDBPaths}->{main} ) {
    $core->log->debug("No main RDB found, creating one");
    $core->log->warn("Could not create 'main' RDB")
      unless $self->createdb('main') ~~ SUCCESS;
  }
  
  return $self
}

sub dbexists {
  my ($self, $rdb) = @_;
  return 1 if $self->{RDBPaths}->{$rdb};
  return
}

sub createdb {
  my ($self, $rdb) = @_;
  return RDB_INVALID_NAME unless $rdb
    and $rdb =~ /^[A-Za-z0-9]+$/;
  return RDB_EXISTS if $self->{RDBPaths}->{$rdb};
  
  my $core = $self->{core};
  $core->log->debug("attempting to create RDB $rdb");
  
  my $path = $self->{RDBDir} ."/". $rdb .".rdb";
  $self->{RDBPaths}->{$rdb} = $path;

  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  unless ( ref $db && $db->get_path eq $path ) {
    $core->log->error("Could not switch to RDB $rdb at $path");
    return RDB_DBFAIL
  }
  
  unless ( $db->dbopen ) {
    $core->log->error("dbopen failure for $rdb in createdb");
    delete $self->{RDBPaths}->{$rdb};
    return RDB_DBFAIL
  }
  
  $db->dbclose;
  
  $core->log->info("Created RDB $rdb");
  
  return SUCCESS
}

sub deldb {
  my ($self, $rdb) = @_;
  my $core = $self->{core};
  
  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};
  
  my $path = $self->{RDBPaths}->{$rdb};
  
  unless (-e $path && ( -f $path || -l $path ) ) {
    $core->log->error(
      "Cannot delete RDB $rdb - $path not found or not a file"
    );
    return RDB_NOSUCH
  }
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  unless ( ref $db && $db->get_path eq $path ) {
    $core->log->error("deldb failure; cannot switch to $rdb");
    return RDB_DBFAIL
  }
  
  unless ( $db->dbopen ) {
    $core->log->error("dbopen failure for $rdb in deldb");
    $core->log->error("Refusing to unlink, admin should investigate.");
    return RDB_DBFAIL
  }
  $db->dbclose;

  unless ( unlink($path) ) {
    $core->log->error("Cannot unlink RDB $rdb at $path: $!");
    return RDB_FILEFAILURE
  }
  
  delete $self->{RDBPaths}->{$rdb};
  $self->{CURRENT} = undef;
  undef $db;
  
  $core->log->info("Deleted RDB $rdb");
  
  return SUCCESS
}

sub del {
  my ($self, $rdb, $key) = @_;
  my $core = $self->{core};
  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  my $path = $self->{RDBPaths}->{$rdb};
  
  unless ( ref $db && $db->get_path eq $path ) {
    $core->log->error("del failure; cannot switch to $rdb");
    return RDB_DBFAIL
  }
  
  unless ( $db->dbopen ) {
    $core->log->error("dbopen failure for $rdb in del");
    return RDB_DBFAIL
  }
  
  unless ( $db->get($key) ) {
    $db->dbclose;
    $core->log->debug("no such item: $key in $rdb");
    return RDB_NOSUCH_ITEM
  }
  
  unless ( $db->del($key) ) {
    $db->dbclose;
    $core->log->warn("failure in db->del for $key in $rdb");
    return RDB_DBFAIL
  }
  
  ## FIXME invalidate search cache
  
  $db->dbclose;
  return SUCCESS
}

sub get {
  my ($self, $rdb, $key) = @_;
  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};
  my $core = $self->{core};
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  my $path = $self->{RDBPaths}->{$rdb};
  
  unless ( ref $db && $db->get_path eq $path ) {
    $core->log->error("get failure; cannot switch to $rdb");
    return RDB_DBFAIL
  }
  
  unless ( $db->dbopen ) {
    $core->log->error("dbopen failure for $rdb in get");
    return RDB_DBFAIL
  }
  
  my $value = $db->get($key);
  $value = RDB_NOSUCH_ITEM unless defined $value;
  
  $db->dbclose;
  return $value
}

sub get_keys {
  my ($self, $rdb) = @_;
  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};
  my $core = $self->{core};
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  my $path = $self->{RDBPaths}->{$rdb};
  unless ( ref $db && $db->get_path eq $path ) {
    $core->log->error("get_keys failure; cannot switch to $rdb");
    return RDB_DBFAIL
  }
  
  unless ( $db->dbopen ) {
    $core->log->error("dbopen failure for $rdb in get_keys");
    return RDB_DBFAIL
  }
  
  my @dbkeys = $db->keys;
  $db->dbclose;
  return @dbkeys
}

sub put {
  my ($self, $rdb, $ref) = @_;
  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};
  my $core = $self->{core};
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  my $path = $self->{RDBPaths}->{$rdb};
  unless ( ref $db && $db->get_path eq $path ) {
    $core->log->error("put failure; cannot switch to $rdb");
    return RDB_DBFAIL
  }
  
  unless ( $db->dbopen ) {
    $core->log->error("dbopen failure for $rdb in put");
    return RDB_DBFAIL
  }
  
  my $newkey = $self->_gen_unique_key($ref);
  
  unless ( $db->put($newkey, $ref) ) {
    $db->dbclose;
    return RDB_DBFAIL
  }
  
  ## FIXME invalidate cache
  $db->dbclose;
  return $newkey
}

sub random {
  my ($self, $rdb) = @_;
  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};
  my $core = $self->{core};
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  my $path = $self->{RDBPaths}->{$rdb};
  unless ( ref $db && $db->get_path eq $path ) {
    $core->log->error("random failure; cannot switch to $rdb");
    return RDB_DBFAIL
  }
  
  unless ( $db->dbopen ) {
    $core->log->error("dbopen failure for $rdb in random");
    return RDB_DBFAIL
  }
  
  my @dbkeys = $db->keys;
  unless (@dbkeys) {
    $db->dbclose;
    return RDB_NOSUCH_ITEM
  }
  
  my $randkey = $dbkeys[rand @dbkeys];
  my $ref = $db->get($randkey);
  unless (ref $ref eq 'HASH') {
    $db->dbclose;
    $core->log->error("Broken DB? item $randkey in $rdb not a hash");
    return RDB_DBFAIL
  }
  $db->dbclose;
  
  $ref->{DBKEY} = $randkey;
  return $ref
}

sub search {
  my ($self, $rdb, $glob) = @_;
  
  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};

  my $core = $self->{core};
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  my $path = $self->{RDBPaths}->{$rdb};
  unless ( ref $db && $db->get_path eq $path ) {
    $core->log->error("search failure; cannot switch to $rdb");
    return RDB_DBFAIL
  }
  
  ## FIXME hit search cache first

  my $re = glob_to_re_str($glob);
  $re = qr/$re/i;

  unless ( $db->dbopen ) {
    $core->log->error("dbopen failure for $rdb in search");
    return RDB_DBFAIL
  }
  
  my @matches;
  for my $dbkey ($db->keys) {
    my $ref = $db->get($dbkey) // next;
    my $str = $ref->{String} // '';
    push(@matches, $dbkey) if $str =~ $re;
  }
  
  $db->dbclose;
  
  ## FIXME push back to cache
  
  return wantarray ? @matches : [ @matches ] ;
}

sub _gen_unique_key {
  my ($self, $ref) = @_;
  my $db = $self->{CURRENT} || return;
  my $stringified = $ref->{String}.rand.Time::HiRes::time();
  my $digest = sha1_hex($stringified);
  my @splitd = split //, $digest;
  my $newkey = join '', splice(@splitd, -4);
  $newkey .= pop @splitd while exists $db->{Tied}{$newkey} and @splitd;
  return $newkey
}

sub _rdb_switch {
  my ($self, $rdb) = @_;
  my $core = $self->{core};
  my $path = $self->{RDBPaths}->{$rdb};
  unless ($path) {
    $core->log->error("_rdb_switch failed; no path for $rdb");
    return
  }
  
  $self->{CURRENT} = Cobalt::DB->new(
    File => $path,
  ) or $self->{CURRENT} = undef;
}

1;
