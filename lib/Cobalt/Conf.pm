package Cobalt::Conf;

## Cobalt::Conf
## Looks for the following YAML confs:
##   etc/cobalt.conf
##   etc/channels.conf
##   etc/plugins.conf
##
## Plguins can specify their own config files to load
## See plugins.conf for more information.

use 5.12.1;
use strict;
use warnings;
use Carp;

use Moose;
use namespace::autoclean;

use File::Slurp;
use YAML::Syck;

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

  ## Core (cobalt.conf)
  $conf->{path_cobalt_cf} = $conf->{path}."/cobalt.conf";
  croak "cannot find cobalt.conf at $conf->{path}"
    unless -f $conf->{path_cobalt_cf};

  my $cf_core = read_file( $conf->{path_cobalt_cf} );
  $conf->{core} = Load $cf_core;

  ## Channels (channels.conf)
  $conf->{path_chan_cf} = $conf->{path}."/channels.conf" ;
  croak "cannot find channels.conf at $conf->{path}"
    unless -f $conf->{path_chan_cf};

  my $cf_chan = read_file( $conf->{path_chan_cf} );
  $conf->{channels} = Load $cf_chan;

  ## Plugins (plugins.conf)
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

    ## see if plugins.conf had "Opts" for this entry
    ## typically should be a hash, fe.x:
    ## Opts:
    ##   Level: 1
    ## (although the option to use an array is there)
    ## typically used for plugins that have other opts but don't
    ## have their own conf file
    if ($conf->{plugins}->{$plugin}->{Opts}
        && ref $conf->{plugins}->{$plugin}->{Opts}) 
    {
      ## if Opts are specified, reference from ->{plugin_cf}->{$pkg}->{PluginOpts}
      ## makes it easier for plugins to grab their 'Opts' from plugins.conf
      $conf->{plugin_cf}->{$pkg}->{PluginOpts} = 
        $conf->{plugins}->{$plugin}->{Opts};
    }
  }

  return $conf
}


__PACKAGE__->meta->make_immutable;
no Moose; 1;
