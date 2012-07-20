package Bot::Cobalt::Conf::File;
our $VERSION = '0.013';

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Bot::Cobalt::Common qw/:types/;

use Bot::Cobalt::Serializer;

use Try::Tiny;


with 'Bot::Cobalt::Conf::Role::Reader';


has 'path' => (
  required => 1,

  is  => 'rwp',
  isa => Str,
);

has 'cfg_as_hash' => (
  lazy => 1,
  
  is  => 'rwp',
  isa => HashRef, 
  
  builder => '_build_cfg_hash',
);

has 'debug' => (
  is  => 'rw',
  isa => Bool,
  
  default => sub { 0 },
);

sub BUILD {
  my ($self) = @_;
  $self->cfg_as_hash
}

sub _build_cfg_hash {
  my ($self) = @_;

  if ($self->debug) {
    warn 
      ref $self, " (debug) reading cfg_as_hash from ", $self->path, "\n"
  }
  
  my $cfg = $self->readfile( $self->path );

  try {
    $self->validate($cfg)
  } catch {
    croak "Conf validation failed for ". $self->path .": $_"
  };
  
  $cfg
}

sub rehash {
  my ($self) = @_;
  
  $self->_set_cfg_as_hash( $self->_build_cfg_hash )
}

sub validate {
  my ($self, $cfg) = @_;
  
  1
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Conf::File - Base class for Bot::Cobalt cfg files

=head1 SYNOPSIS

  ## Subclass for a particular cfg file:
  package MyPackage::Conf;
  use Moo;
  extends 'Bot::Cobalt::Conf::File';

  # An attribute filled from loaded YAML cfg_as_hash:
  has 'opts' => (
    lazy => 1,
    
    is  => 'rwp',

    default => sub {
      my ($self) = @_;

      $self->cfg_as_hash->{Opts}
    },
  );

  # Override validate() to check for correctness:
  around 'validate' => sub {
    my ($orig, $self, $cfg_hash) = @_;
    
    die "Missing directive: Opts"
      unless defined $cfg_hash->{Opts};

    1
  };

  ## Use cfg file elsewhere:
  package MyPackage;
  
  my $cfg = MyPackage::Conf->new(
    path => $path_to_yaml_cfg,
  );

  my $opts = $cfg->opts;

=head1 DESCRIPTION

This is the base class for L<Bot::Cobalt> configuration files.
It consumes the Bot::Cobalt::Conf::Role::Reader role and loads a 
configuration hash from a YAML file specified by the required B<path> 
attribute.

The B<validate> method is called at load-time and passed the 
configuration hash before it is loaded to the B<cfg_as_hash> attribute; 
this method can be overriden by subclasses to do some load-time checking 
on a configuration file.

=head2 path

The B<path> attribute is required at construction-time; this is the 
actual path to the YAML configuration file.

=head2 cfg_as_hash

The B<cfg_as_hash> attribute returns the loaded file as a hash reference. 
This is normally used by subclasses to fill attributes, and not used 
directly.

=head2 rehash

The B<rehash> method attempts to reload the current
B<cfg_as_hash> from B<path>.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
