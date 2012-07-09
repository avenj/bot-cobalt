package Bot::Cobalt::Conf;
our $VERSION = '0.012';

use Carp;
use Moo;

use strictures 1;

use Bot::Cobalt::Common qw/:types/;

use Bot::Cobalt::Conf::File::Core;
use Bot::Cobalt::Conf::File::Channels;
use Bot::Cobalt::Conf::File::Plugins;

use File::Spec;

use Scalar::Util qw/blessed/;


has 'etc'   => (
  required => 1,

  is  => 'rw', 
  isa => Str, 
);

has 'debug' => (
  is  => 'rw', 
  isa => Bool, 
  
  default => sub { 0 } 
);

has 'path_to_core_cf' => (
  lazy => 1,

  is  => 'rwp',
  isa => Str,
  
  default => sub {
    my ($self) = @_;

    File::Spec->catfile(
      $self->etc,
      'cobalt.conf'
    )
  },
);

has 'path_to_channels_cf' => (
  lazy => 1,

  is  => 'rwp',
  isa => Str,
  
  default => sub {
    my ($self) = @_;
    
    File::Spec->catfile(
      $self->etc,
      'channels.conf'
    )
  },
);

has 'path_to_plugins_cf' => (
  lazy => 1,

  is  => 'rwp',
  isa => Str,
  
  default => sub {
    my ($self) = @_;
    
    File::Spec->catfile(
      $self->etc,
      'plugins.conf'
    )
  },
);


has 'core' => (
  lazy => 1,
  
  is  => 'rwp',
  isa => sub {
    blessed $_[0] and $_[0]->isa('Bot::Cobalt::Conf::File::Core')
      or die "core() should be a Bot::Cobalt::Conf::File::Core"
  },
  
  default => sub {
    my ($self) = @_;

    Bot::Cobalt::Conf::File::Core->new(
      path => $self->path_to_core_cf,
    )
  },
);

has 'channels' => (
  lazy => 1,
  
  is  => 'rwp',
  isa => sub {
    blessed $_[0] and $_[0]->isa('Bot::Cobalt::Conf::File::Channels')
      or die "channels() should be a Bot::Cobalt::Conf::File:Channels"
  },
  
  default => sub {
    my ($self) = @_;

    Bot::Cobalt::Conf::File::Channels->new(
      path => $self->path_to_channels_cf,
    )
  },
);

has 'plugins' => (
  lazy => 1,
  
  is  => 'rwp',
  isa => sub {
    blessed $_[0] and $_[0]->isa('Bot::Cobalt::Conf::File::Plugins')
      or die "plugins() should be a Bot::Cobalt::Conf::File::Plugins"
  },
  
  default => sub {
    my ($self) = @_;

    Bot::Cobalt::Conf::File::Plugins->new(
      path   => $self->path_to_plugins_cf,
      etcdir => $self->etc,
    )
  },
);


1;
__END__

=pod


=cut
