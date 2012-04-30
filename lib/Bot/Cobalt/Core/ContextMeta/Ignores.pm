package Bot::Cobalt::Core::ContextMeta::Ignores;

use 5.10.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Utils qw/normalize_mask/;
use Cobalt::Common;

extends 'Bot::Cobalt::Core::ContextMeta';

has 'core' => ( is => 'rw', isa => Object, lazy =>,
  default => sub {
    require Bot::Cobalt::Core;
    croak "No Cobalt::Core instance found"
     unless Bot::Cobalt::Core->is_instanced;
    Bot::Cobalt::Core->instance
  }
);

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

  $self->$orig($context, $mask, $meta)
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Core::Global::IgnoreList - The globally-shared ignore list

=head1 SYNOPSIS

  FIXME

=head1 DESCRIPTION

Simple ignore list management; this is used by L<Bot::Cobalt::Core> to 
provide a global ignore list for use by L<Cobalt::IRC> and the core 
plugin set.

Plugin authors can, of course, create their own IgnoreList object and 
use it to manage ignores and similar lists internally.

=head1 METHODS

=head2 add

  $core->ignore->add($context, $mask, $reason, $addedby)

Add a new mask to a context's ignore list, possibly with some optional 
metadata.

The mask will be normalized before adding; the mask that was actually 
added will be returned on success.

=head2 del

  $core->ignore->del($context, $mask)

Delete a specific mask on a context's ignore list.

=head2 clear

  $core->ignore->clear($context)

Clear a context's ignore list entirely.

=head2 list

  ## Retrieve list of ignored masks for a context
  my @ignores_for_context = $core->ignore->list($context);

  ## Retrieve actual ignore list hash reference for a context
  my $ignore_ref_for_context = $core->ignore->list($context);

Returns either a list of ignores in list context or the actual reference 
to the ignore list in scalar context.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
