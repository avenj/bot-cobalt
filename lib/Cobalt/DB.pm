package Cobalt::DB;
our $VERSION = '0.01';

## ->new(File => $path)
##  To use a different lockfile:
## ->new(File => $path, LockFile => $lockpath)
## Represents a BerkDB

use 5.12.1;
use strict;
use warnings;
use Carp;

use DB_File;
use Fcntl;

use File::Spec;

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;
  
  my %args = @_;
  unless ($args{File}) {
    croak "Constructor requires a specified File";
  }

  my $path = $args{File};
  my ($vol, $dir, $dbfile) = File::Spec->splitpath($path);
  croak "no file specified" unless $dbfile;
  croak "cannot find $path" unless -e $dbfile;
  ## FIXME volume ... ?
  $self->{LockFile}     = $args{LockFile} ? 
                          $args{LockFile} 
                        : $dir . "/.lock.".$dbfile ;

  $self->{DatabasePath} = $path;
  
  ## FIXME perms arg
  $self->{Perms} = 0644;

  return $self
}

sub _dbopen {
  my ($self) = shift;
  ## FIXME lockfile (->fd method?)
  my $path = $self->{DatabasePath};
  tie $self->{DB}, "DB_File", $path,
      O_CREAT|O_RDWR, $self->{Perms}, $DB_HASH
      or croak "failed db open: $path: $!"
  ;
}

sub _dbclose {
  my $self = shift;
  ## FIXME unlock
  untie $self->{DB};
}

sub get_key {
 my ($self, $key) = @_;
 $self->_dbopen;
 my %h = $self->{DB};
 my $value = $h{$key} // undef;
 $self->_dbclose;
 return $value
}

sub set_key {
  my ($self, $key, $value) = @_;
  $self->_dbopen;
  my %h = $self->{DB};
  $h{$key} = $value;
  $self->_dbclose;
}

sub del_key {
  my ($self, $key) = @_;
  $self->_dbopen;
  my %h = $self->{DB};
  return undef unless exists $h{$key};
  delete $h{$key};
  return 1
}

1;
