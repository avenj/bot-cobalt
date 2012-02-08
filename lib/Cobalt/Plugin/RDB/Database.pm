package Cobalt::Plugin::RDB::Database;
our $VERSION = '0.20';

## Cobalt2 RDB manager

use Moose;

use Cobalt::DB;

use Cobalt::Plugin::RDB::Constants;
use Cobalt::Plugin::RDB::SearchCache;

use Digest::SHA1 qw/sha1_hex/;

use File::Basename;
use File::Spec;

use Time::HiRes;

has 'RDBDir' => (
  is  => 'ro',
  isa => 'Str',
  required => 1,
);

has 'core' => (
  is  => 'ro',
  isa => 'Object',
  required => 1,
);

has 'RDBPaths' => (
  is => 'rw',
  isa => 'HashRef',
  default => sub { {} },
);

has 'SearchCache' => (
  is => 'rw',
  isa => 'Object',
);

sub BUILD {
  ## Initialization -- Find our RDBs
  my ($self) = @_;
  my $core = $self->core;

  $self->SearchCache( Cobalt::Plugin::RDB::SearchCache->new(
      MaxKeys => 30,
    ),
  );

  my $rdbdir = $self->RDBDir;

  unless (-d $rdbdir) {
    $core->log->error("Could not find RDBDir: $rdbdir");
    return RDB_NOSUCH
  }

  my @paths = glob($rdbdir."/*.rdb");
  
  for my $path (@paths) {
    my $abs_path = File::Spec->rel2abs($path);
    my $rdb_name = fileparse($path, '.rdb');
    ## attempt to open this RDB to see if it's busted:
    unless ( $self->_dbopen($rdb_name) ) {
      $core->log->error("dbopen failure for $rdb_name");
      next
    }
    $self->RDBPaths->{$rdb_name} = $abs_path;
  }
}

sub createdb {
  ## Initialize an empty RDB
  ## return RDB_EXISTS, RDB_DBFAIL, SUCCESS
  my ($self, $rdb) = @_;

  return RDB_INVALID_NAME unless $rdb =~ /^[A-Za-z0-9]+$/;

  return RDB_EXISTS if $self->RDBPaths->{$rdb};
  
  my $path = $self->RDBDir ."/". $rdb .".rdb";
  $self->RDBPaths->{$rdb} = $path;
  my $cdb = $self->_dbopen($rdb);
  unless ($cdb) {
    delete $self->RDBPaths->{$rdb};
    return RDB_DBFAIL
  }

  ## these dbcloses are optional, but good practice
  ## Cobalt::DB will dbclose at DESTROY time
  $cdb->dbclose;

  return SUCCESS  
}

sub deldb {
  my ($self, $rdb) = @_;
  my $core = $self->core;

  return RDB_NOSUCH unless $self->RDBPaths->{$rdb};
  
  my $path = $self->RDBPaths->{$rdb};
  
  unless (-e $path) {
    $core->log->error("Cannot delete RDB $rdb - $path not found");
    return RDB_NOSUCH
  }

  my $cdb = $self->_dbopen($rdb);  
  unless ($cdb) {
    $core->log->error("Cannot delete RDB $rdb - might not be a valid DB");
    return RDB_DBFAIL
  }
  $cdb->dbclose;
  
  unless ( unlink($path) ) {
    $core->log->error("Cannot delete RDB $rdb - unlink: ${path}: $!");
    return RDB_FILEFAILURE
  }

  delete $self->RDBPaths->{$rdb};
  return SUCCESS
}

sub del {
  my ($self, $rdb, $key) = @_;

  return RDB_NOSUCH unless $self->RDBPaths->{$rdb};

  my $cdb = $self->_dbopen($rdb);
  
  return RDB_DBFAIL      unless $cdb;
  return RDB_NOSUCH_ITEM unless $cdb->get($key);  
  return RDB_DBFAIL      unless $cdb->del($key);
  
  $cdb->dbclose;  
  $self->SearchCache->invalidate($rdb);

  return SUCCESS
}

sub get {
  ## Grab a specific key from RDB
  my ($self, $rdb, $key) = @_; 
  return RDB_NOSUCH unless $self->RDBPaths->{$rdb};
  
  my $cdb = $self->_dbopen($rdb);
  return RDB_DBFAIL unless $cdb;
  
  my $value = $cdb->get($key);
  return RDB_NOSUCH_ITEM unless defined $value;
  $cdb->dbclose;
  return $value
}

sub get_keys {
  my ($self, $rdb) = @_;
  return RDB_NOSUCH unless $self->RDBPaths->{$rdb};
  my $cdb = $self->_dbopen($rdb);
  return RDB_DBFAIL unless $cdb;
  my @keys = $cdb->keys() || ();
  $cdb->dbclose;
  return @keys
}

sub put {
  my ($self, $rdb, $ref) = @_;
  ## Add new entry to RDB
  ## Return the item's key
  return RDB_NOSUCH unless $self->RDBPaths->{$rdb};
  
  my $cdb = $self->_dbopen($rdb);
  return RDB_DBFAIL unless $cdb;

  my $key = $self->_gen_unique_key($cdb, $rdb, $ref);

  return RDB_DBFAIL unless $cdb->put($key, $ref);
  $self->SearchCache->invalidate($rdb);
  $cdb->dbclose;
  return $key
}

sub random {
  my ($self, $rdb) = @_;
  ## Grab a random entry from specified rdb
  return RDB_NOSUCH unless $self->RDBPaths->{$rdb};
  
  my $cdb = $self->_dbopen($rdb);
  return RDB_DBFAIL unless $cdb;
  
  my @dbkeys = $cdb->keys();
  return RDB_NOSUCH_ITEM unless @dbkeys;
  
  my $randkey = $dbkeys[rand @dbkeys];
  my $ref = $cdb->get($randkey);
  return RDB_NOSUCH_ITEM unless ref $ref;
  
  return $ref
}

sub search {
  my ($self, $rdb, $glob) = @_;
  ## Search RDB entries, get an array(ref) of matching keys

  return RDB_NOSUCH unless $self->RDBPaths->{$rdb};

  ## hit the search cache first
  my @cached_result = $self->SearchCache->fetch($rdb, $glob);
  
  if (@cached_result) { 
    return wantarray ? @cached_result : [ @cached_result ]
  }

  my $re = glob_to_re_str($glob);
  $re = qr/$re/i;

  my $cdb = $self->_dbopen($rdb);
  return DB_DBFAIL unless $cdb;

  my @matches;  
  for my $dbkey ($cdb->keys) {
    my $ref = $cdb->get($dbkey) // next;
    my $str = $ref->{String} // '';
    push(@matches, $dbkey) if $str =~ $re;
  }
  
  $cdb->dbclose;
  
  ## Push resultset to the SearchCache
  $self->SearchCache->cache($rdb, $glob, [ @matches ]);
  
  return wantarray ? @matches : [ @matches ] ;
}

sub _dbopen {
  my ($self, $rdb) = @_;
  my $core = $self->core;
  my $path = $self->RDBPaths->{$rdb};
  unless ($path) {
    $core->log->error("_dbopen failed; no path for $rdb?");
    return
  }

  unless (-e $path) {
    $core->log->error("_dbopen failed; $path nonexistant");
    return
  }
  
  my $cdb = Cobalt::DB->new(
    File => $path
  );
  
  unless ( $cdb->dbopen ) {
    $core->log->error("Cobalt::DB dbopen failure for $rdb");
    return
  }
  
  ## Return the $cdb obj for this rdb
  return $cdb
}

sub _gen_unique_key {
  ## _gen_unique_key($cdb, $rdb, $ref)
  ##  Create unique key for this rdb item
  my ($self, $cdb, $rdb, $ref) = @_;
  
  unless (ref $cdb and $cdb->{Tied}) {
    warn "_gen_unique_key cannot find Cobalt::DB tied hash";
  }

  my $stringified = $ref->{String} . Time::HiRes::time ;
  my $digest = sha1_hex($stringified);
  
  ## start at 4, add back chars if it's not unique:
  my @splitd = split //, $digest;
  my $newkey = join '', splice(@splitd, -4);
  $newkey .= pop @splitd while exists $cdb->{Tied}{$newkey} and @splitd;
  return $newkey  
}

no Moose; 1;
