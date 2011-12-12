package Cobalt::Conf;

use 5.14.1;

use Moose;

use Carp;

use File::Slurp;

use YAML::Syck;

use namespace::autoclean;

has 'etc' => (
  is => 'ro',
  isa => 'Str',
  required => 1
);

sub read_cfg {
  my ($self) = @_;
  my $conf = { };

  $conf->{path} = $self->etc;
  croak "can't find confdir: $conf->{path}" unless -d $conf->{path};

  ## Core
  $conf->{path_cobalt_cf} = $conf->{path}."/cobalt.conf";
  croak "cannot find cobalt.conf at $conf->{path}"
    unless -f $conf->{path_cobalt_cf};

  my $cf_core = read_file( $conf->{path_cobalt_cf} );
  $conf->{core} = Load $cf_core;

  ## Channels
  $conf->{path_chan_cf} = $conf->{path}."/channels.conf" ;
  croak "cannot find channels.conf at $conf->{path}"
    unless -f $conf->{path_chan_cf};

  my $cf_chan = read_file( $conf->{path_chan_cf} );
  $conf->{channels} = Load $cf_chan;

  ## Plugins
  $conf->{path_plugins_cf} = $conf->{path}."/plugins.conf";
  croak "can't find plugins.conf at $conf->{path}" unless -f $conf->{path_plugins_cf};
  my $cf_yml_plugins = read_file($conf->{path_plugins_cf});
  $conf->{plugins} = Load $cf_yml_plugins;


  # Plugin-specific configs, relative to etc/
  for my $plugin (keys %{ $conf->{plugins} })
  {
    my $pkg = $conf->{plugins}->{$plugin}->{Module} || next;
    my $cf_plugin = $conf->{plugins}->{$plugin}->{Config} || next;
    croak "can't find plugin conf $cf_plugin"
      unless -f $conf->{path}."/".$cf_plugin;

    my $cf_yml = read_file($conf->{path}."/".$cf_plugin);
    $conf->{plugin_cf}->{$pkg} = Load $cf_yml;
  }

  return $conf
}


__PACKAGE__->meta->make_immutable;
no Moose; 1;
