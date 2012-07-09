package Bot::Cobalt::Conf::File::PerPlugin;

use strictures 1;

use Moo;
use Carp;

use Bot::Cobalt::Common qw/:types/;

use Scalar::Util qw/blessed/;


with 'Bot::Cobalt::Conf::Role::Reader';


has 'extra_opts' => (
  ## Overrides the plugin-specific cfg.
  lazy => 1,
  
  is  => 'ro',
  isa => HashRef,

  predicate => 'has_extra_opts',
  writer    => 'set_extra_opts',
);

has 'module' => (
  required => 1,
  
  is  => 'rwp',
  isa => Str,
);

has 'priority' => (
  lazy => 1,
  
  is  => 'ro',
  isa => Num,
  
  writer    => 'set_priority',
  predicate => 'has_priority',
);

has 'config_file' => (
  lazy => 1,
  
  is  => 'ro',
  isa => Str,
  
  writer    => 'set_config_file',
  predicate => 'has_config_file',
);

has 'autoload' => (
  lazy => 1,
  
  is  => 'ro',
  isa => Bool,

  default => sub { 1 },
);

has 'opts' => (
  lazy => 1,
  
  is  => 'rwp',
  isa => HashRef,
  
  builder => '_build_opts',
);

sub _build_opts {
  my ($self) = @_;
  
  ##  - readfile() our config_file if we have one
  ##  - override with extra_opts if we have any

  my $opts_hash;
  
  if ( $self->has_config_file ) {
    $opts_hash = $self->readfile( $self->config_file )
  }

  if ( $self->has_extra_opts ) {
    ## 'Opts' directive in plugins.conf was passed in
    $opts_hash->{$_} = $self->extra_opts->{$_}
      for keys %{ $self->extra_opts };
  }

  $opts_hash 
}

1;
__END__
