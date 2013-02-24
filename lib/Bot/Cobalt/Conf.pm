package Bot::Cobalt::Conf;
our $VERSION = '0.015';

use Carp;
use Moo;

use strictures 1;

use Bot::Cobalt::Common qw/:types/;

use Bot::Cobalt::Conf::File::Core;
use Bot::Cobalt::Conf::File::Channels;
use Bot::Cobalt::Conf::File::Plugins;

use File::Spec;

use Scalar::Util qw/blessed/;


use namespace::clean -except => 'meta';



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

  is  => 'ro',

  predicate => 'has_core',
  writer    => 'set_core',

  isa => sub {
    blessed $_[0] and $_[0]->isa('Bot::Cobalt::Conf::File::Core')
      or die "core() should be a Bot::Cobalt::Conf::File::Core"
  },

  default => sub {
    my ($self) = @_;

    Bot::Cobalt::Conf::File::Core->new(
      debug => $self->debug,
      path  => $self->path_to_core_cf,
    )
  },
);

has 'channels' => (
  lazy => 1,

  is  => 'ro',

  predicate => 'has_channels',
  writer    => 'set_channels',

  isa => sub {
    blessed $_[0] and $_[0]->isa('Bot::Cobalt::Conf::File::Channels')
      or die "channels() should be a Bot::Cobalt::Conf::File:Channels"
  },

  default => sub {
    my ($self) = @_;

    Bot::Cobalt::Conf::File::Channels->new(
      debug => $self->debug,
      path  => $self->path_to_channels_cf,
    )
  },
);

has 'plugins' => (
  lazy => 1,

  is  => 'ro',

  predicate => 'has_plugins',
  writer    => 'set_plugins',

  isa => sub {
    blessed $_[0] and $_[0]->isa('Bot::Cobalt::Conf::File::Plugins')
      or die "plugins() should be a Bot::Cobalt::Conf::File::Plugins"
  },

  default => sub {
    my ($self) = @_;

    Bot::Cobalt::Conf::File::Plugins->new(
      debug  => $self->debug,
      path   => $self->path_to_plugins_cf,
      etcdir => $self->etc,
    )
  },
);


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Conf - Bot::Cobalt configuration manager

=head1 SYNOPSIS

  my $cfg = Bot::Cobalt::Conf->new(
    etc => $path_to_etc_dir,
  );

  ## Or with specific paths
  ## (Still need an etcdir)
  my $cfg = Bot::Cobalt::Conf->new(
    etc => $path_to_etc_dir,
    path_to_core_cf     => $core_cf_path,
    path_to_channels_cf => $chan_cf_path,
    path_to_plugins_cf  => $plugins_cf_path,
  );

  ## Bot::Cobalt::Conf::File::Core
  $cfg->core;

  ## Bot::Cobalt::Conf::File::Channels
  $cfg->channels;

  ## Bot::Cobalt::Conf::File::Plugins
  $cfg->plugins;

=head1 DESCRIPTION

A configuration manager class for L<Bot::Cobalt> -- L<Bot::Cobalt::Core>
loads and accesses configuration objects via instances of this class.

=head1 SEE ALSO

L<Bot::Cobalt::Conf::File::Core>

L<Bot::Cobalt::Conf::File::Channels>

L<Bot::Cobalt::Conf::File::Plugins>

L<Bot::Cobalt::Conf::File::PerPlugin>

L<Bot::Cobalt::Conf::File>

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
