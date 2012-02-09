package Cobalt::Plugin::RDB::SearchCache;
our $VERSION = '0.21';

## This is a fairly generic in-memory cache object.
##
## It's intended for use with Plugin::RDB, but will likely work for 
## just about situation where you want to store a set number of keys 
## mapping an identifier to an array reference.
##
## This can be useful for caching the results of deep searches against 
## Cobalt::DB instances, for example.
##
## This may get moved out to the core lib directory, in which case this 
## module will become a placeholder.

use 5.12.1;
use strict;
use warnings;

use Time::HiRes;

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;
    
  my %opts = @_;
  
  $self->{Cache} = { };
  
  $self->{MAX_KEYS} = $opts{MaxKeys} || 30;
  
  return $self
}

sub cache {
  my ($self, $rdb, $match, $resultset) = @_;
  ## should be passed rdb, search str, and array of matching indices
  
  return unless $rdb and $match;
  $resultset = [ ] unless $resultset and ref $resultset eq 'ARRAY';

  ## _shrink will do the right thing depending on size of cache
  ## (MaxKeys can be used to adjust cachesize per-rdb 'on the fly')
  $self->_shrink($rdb);
  
  $self->{Cache}->{$rdb}->{$match} = {
    TS => Time::HiRes::time(),
    Results => $resultset,
  };
}

sub fetch {
  my ($self, $rdb, $match) = @_;
  
  return unless $rdb and $match;
  return unless $self->{Cache}->{$rdb} 
         and $self->{Cache}->{$rdb}->{$match};

  my $ref = $self->{Cache}->{$rdb}->{$match};
  wantarray ? return @{ $ref->{Results} } 
            : return $ref->{Results}  ;
}

sub invalidate {
  my ($self, $rdb) = @_;
  ## should be called on add/del operations 
  ## invalidate all
  $self->{Cache} = { } unless $rdb;
  return unless $self->{Cache}->{$rdb};
  return unless scalar keys %{ $self->{Cache}->{$rdb} };  
  return delete $self->{Cache}->{$rdb};
}

sub MaxKeys {
  my ($self, $max) = @_;
  $self->{MAX_KEYS} = $max if defined $max;
  return $self->{MAX_KEYS};
}

sub _shrink {
  my ($self, $rdb) = @_;
  
  return unless $rdb and ref $self->{Cache}->{$rdb};

  my $cacheref = $self->{Cache}->{$rdb};
  return unless scalar keys %$cacheref > $self->MaxKeys;

  my @cached = sort { 
      $cacheref->{$a}->{TS} <=> $cacheref->{$b}->{TS}
    } keys %$cacheref;
  
  my $deleted;
  while (scalar keys %$cacheref > $self->MaxKeys) {
    my $nextkey = shift @cached;
    ++$deleted if delete $cacheref->{$nextkey};
  }
  return $deleted || -1
}

1;
__END__

=pod

=head1 NAME

Cobalt::Plugin::RDB::SearchCache - generic limited-key memory caching

=head1 SYNOPSIS

  ## Add a SearchCache that allows 30 max keys:
  $self->{CacheObj} = Cobalt::Plugin::RDB::SearchCache->new(
    MaxKeys => 30,
  );
  
  ## Push some array of results/indexes to the cache obj:
  my $cache = $self->{CacheObj};
  $cache->cache('MyCache', $key, [ @results ] );
  
  ## Get it back later:
  my @results = $cache->fetch('MyCache', $key);
  
  ## Data changed, invalidate this cache:
  $cache->invalidate('MyCache');
  

=head1 DESCRIPTION

B<SearchCache> is a very simplistic mechanism for storing some arrays of data 
in a hash with a set ceiling limit of keys.

If the number of keys in the specified cache grows above B<MaxKeys>, 
older entries will be removed from the hash to make room for the new 
set.

This can be useful for caching the result of deep searches against 
large L<Cobalt::DB> databases, for example.

This interface is used by L<Cobalt::Plugin::RDB> and 
L<Cobalt::Plugin::Info3>.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
