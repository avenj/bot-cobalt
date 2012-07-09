package Bot::Cobalt::Conf::File::Plugins;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Scalar::Util qw/blessed/;

use Bot::Cobalt::Common qw/:types/;

use Bot::Cobalt::Conf::File::PerPlugin;

use File::Spec;


extends 'Bot::Cobalt::Conf::File';


has 'etcdir' => (
  required => 1,
  
  is  => 'rwp',
  isa => Str,
);


has '_per_plug_objs' => (
  lazy => 1,
  
  is  => 'ro',
  isa => HashRef,

  builder => '_build_per_plugin_objs',  
);


sub _build_per_plugin_objs {
  my ($self) = @_;
  
  ##  Create PerPlugin cf objs for each plugin
  my $plugin_objs = {};
  for my $alias (keys %{ $self->cfg_as_hash }) {
    $plugin_objs->{$alias} = $self->_create_perplugin_obj($alias);
  }

  $plugin_objs
}

sub _create_perplugin_obj {
  my ($self, $alias) = @_;
  
  my $this_cfg = $self->cfg_as_hash->{$alias}
    || confess "_create_perplugin_obj passed unknown alias $alias";

  my %new_opts;

  $new_opts{module} = $this_cfg->{Module}
    || confess "No Module defined for plugin $alias";

  if (defined $this_cfg->{Config}) {
    my $this_cf_path = $this_cfg->{Config};
    unless ( File::Spec->file_name_is_absolute( $this_cf_path ) ) {
      $this_cf_path = File::Spec->catfile( 
        $self->etcdir,
        $this_cf_path 
      )
    }

    $new_opts{config_file} = $this_cf_path  
  }  

  $new_opts{autoload} = 0
    if $this_cfg->{NoAutoLoad};

  $new_opts{priority} = $this_cfg->{Priority}
    if defined $this_cfg->{Priority};

  if (defined $this_cfg->{Opts}) {
    confess "Opts: directive for plugin $alias is not a hash"
      unless ref $this_cfg->{Opts} eq 'HASH';
    
    $new_opts{extra_opts} = $this_cfg->{Opts};
  }

  Bot::Cobalt::Conf::File::PerPlugin->new(
    %new_opts
  );
}


sub plugin {
  my ($self, $plugin) = @_;
  
  confess "plugin() requires a plugin alias"
    unless defined $plugin;

  confess "No config loaded for plugin alias $plugin"
    unless exists $self->_per_plug_objs->{$plugin};

  $self->_per_plug_objs->{$plugin}
}

sub list_plugins {
  my ($self) = @_;
  
  [ keys %{ $self->_per_plug_objs } ]
}


around 'validate' => sub {
  my ($orig, $self, $cfg) = @_;

  ## FIXME

  1
};


1;
__END__
