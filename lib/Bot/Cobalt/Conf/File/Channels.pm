package Bot::Cobalt::Conf::File::Channels;
our $VERSION = '0.016001';

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Bot::Cobalt::Common qw/:types/;


extends 'Bot::Cobalt::Conf::File';


sub context {
  my ($self, $context) = @_;
  
  croak "context() requires a server context identifier"
    unless defined $context;

  $self->cfg_as_hash->{$context}
}


around 'validate' => sub {
  my ($orig, $self, $cfg) = @_;

  my @contexts;
  die "There are no contexts defined.\n"
    unless @contexts = keys %$cfg;
  
  for my $context (keys %$cfg) {  
    die "Context directive $context is not a hash"
      unless ref $cfg->{$context} eq 'HASH';
  }

  1
};


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Conf::File::Channels - Bot::Cobalt channels conf

=head1 SYNOPSIS

  my $chan_cfg = Bot::Cobalt::Conf::File::Channels->new(
    path => $path_to_channels_cf,
  );
  
  my $hash_for_context = $chan_cfg->context($context_name);

  my $this_channel = $hash_for_context->{$channel} || { };

=head1 DESCRIPTION

This is the L<Bot::Cobalt::Conf::File> subclass for "channels.conf."

This is a core configuration class; plugin authors should use 
B<get_channels_cfg> instead:

  use Bot::Cobalt;
  my $channels_cfg = core()->get_channels_cfg( $context_name );

=head2 context

The 'context' method takes a context name and returns the relevant hash 
of channels.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
