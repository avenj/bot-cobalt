package Bot::Cobalt::Core::Global::IgnoreList;

use 5.10.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Utils qw/normalize_mask/;
use Cobalt::Common;

has '_list' => ( is => 'rw', isa => HashRef, default => sub { {} } );

has 'core' => ( is => 'rw', isa => Object, lazy =>,
  default => sub {
    require Bot::Cobalt::Core;
    croak "No Cobalt::Core instance found"
     unless Bot::Cobalt::Core->is_instanced;
    Bot::Cobalt::Core->instance
  }
);

sub add {
  my ($self, $context, $mask, $reason, $addedby) = @_;
  
  my ($pkg, $line) = (caller)[0,2];
  
  unless (defined $context && defined $mask) {
    $self->core->log->warn(
      "Buggy plugin; Missing arguments in ignore add()",
      "(caller $pkg line $line)";
    );
    return
  }  
  
  $mask    = normalize_mask($mask);
  $addedby = $pkg unless defined $addedby;
  $reason  = "Added by $pkg" unless $reason;
  
  $self->_list->{$context}->{$mask} = {
    AddedBy => $addedby,
    AddedAt => time(),
    Reason  => $reason,
  };
  
  return $mask
}

sub clear {
  my ($self, $context) = @_;
  my ($pkg, $line) = (caller)[0,2];
  
  unless (defined $context) {
    $self->core->log->warn(
      "Buggy plugin; missing arguments in ignore clear()",
      "(caller $pkg line $line)",
    );
  }
  
  return delete $self->_list->{$context}
}

sub del {
  my ($self, $context, $mask) = @_;
  my ($pkg, $line) = (caller)[0,2];
  
  unless (defined $context && defined $mask) {
    $self->core->log->warn(
      "Buggy plugin; Missing arguments in ignore del()",
      "(caller $pkg line $line)";
    );
    return
  }
  
  my $list = $self->_list->{$context} // return;
  
  unless (exists $ignore->{$mask}) {
    $self->core->log->warn(
      "Plugin attempted to del() nonexistant mask $mask",
      "(caller $pkg line $line)";
    );
    return
  }

  return delete $list->{$mask}
}

sub list {
  my ($self, $context) = @_;
  
  my $ignorelist;
  
  if ($context) {
    $ignorelist = $self->_list->{$context} // {};
  } else {
    $ignorelist = $self->_list
  }
  
  return wantarray ? keys %$ignorelist : $ignorelist
}


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Core::Global::IgnoreList - The globally-shared ignore list

=head1 SYNOPSIS

FIXME

=head1 DESCRIPTION

FIXME

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
