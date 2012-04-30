package Bot::Cobalt::Core::ContextMeta::Ignore;

use 5.10.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Utils qw/normalize_mask/;
use Cobalt::Common qw/:types/;

extends 'Bot::Cobalt::Core::ContextMeta';

around 'add' => sub {
  my $orig = shift;
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

  my $meta = {
    AddedBy => $addedby,
    Reason  => $reason,
  };

  $orig->($self, $context, $mask, $meta)
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Core::ContextMeta::Ignores - Ignore list management

=head1 SYNOPSIS

  FIXME

=head1 DESCRIPTION

A L<Bot::Cobalt::Core::ContextMeta> subclass for managing an ignore 
list.

This is used by L<Bot::Cobalt::Core> to 
provide a global ignore list for use by L<Cobalt::IRC> and the core 
plugin set.

FIXME

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
