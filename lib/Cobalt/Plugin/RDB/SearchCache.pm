package Cobalt::Plugin::RDB::SearchCache;
our $VERSION = '0.20';

use 5.12.1;
use Moose;

use Time::HiRes;

has 'Cache' => (
  is => 'rw',
  isa => 'HashRef',
  default => sub { {} },
);

has 'MaxKeys' => (
  is => 'rw',
  isa => 'Int',
  default => 30,
);


sub cache {
  my ($self, $rdb, $match, $resultset) = @_;
  ## should be passed rdb, search str, and array of matching indices
  
  return unless $rdb and $match;
  $resultset = [ ] unless $resultset and ref $resultset eq 'ARRAY';

  ## _shrink will do the right thing depending on size of cache
  ## (MaxKeys can be used to adjust cachesize per-rdb 'on the fly')
  $self->_shrink($rdb);
  
  $self->Cache->{$rdb}->{$match} = {
    TS => Time::HiRes::time(),
    Results => $resultset,
  };
}

sub fetch {
  my ($self, $rdb, $match) = @_;
  
  return unless $rdb and $match;
  return unless $self->Cache->{$rdb} 
         and $self->Cache->{$rdb}->{$match};

  my $ref = $self->Cache->{$rdb}->{$match};
  wantarray ? return @{ $ref->{Results} } 
            : return $ref->{Results}  ;
}

sub invalidate {
  my ($self, $rdb) = @_;
  ## should be called on add/del operations  
  return unless $self->Cache->{$rdb};
  return unless scalar keys $self->Cache->{$rdb};  
  return delete $self->Cache->{$rdb};
}

sub _shrink {
  my ($self, $rdb) = @_;
  
  return unless $rdb and ref $self->Cache->{$rdb};

  my $cacheref = $self->Cache->{$rdb};
  return unless scalar keys %$cacheref > $self->MaxKeys;

  my @cached = sort { 
      $cacheref->{$a}->{TS} <=> $cacheref->{$b}->{TS}
    } keys %$cacheref;
  
  my $deleted;
  while (scalar keys %$cacheref > $self->MaxKeys) {
    my $nextkey = shift @cached;
    ++$deleted if delete $cacheref->{$nextkey};
  }
  return $deleted || 1
}

no Moose; 1;
