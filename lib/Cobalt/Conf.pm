package Cobalt::Conf;
our $VERSION = '0.10';
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

use Cobalt::Serializer;

sub new {
  my $class = shift;
  my $self = {};
  my %args = @_;
  bless $self, $class;

  unless ($args{etc}) {
    croak "constructor requires argument: etc => PATH";
  } else {
    $self->{etc} = $args{etc};
  }

  return $self
}

sub _read_conf {
  ## deserialize a YAML1.0 conf
  my ($self, $relative_to_etc) = @_;

  my $etc = $self->{etc};
  unless (-e $self->{etc}) {
    carp "cannot find etcdir: $self->{etc}";
    return
  }

  my $path = $etc ."/". $relative_to_etc;
  unless (-e $path) {
    carp "cannot find $path at $self->{etc}";
    return
  }

  my $serializer = Cobalt::Serializer->new;
  my $thawed = $serializer->readfile( $path );

  unless ($thawed) {
    carp "Serializer failure!";
    return
  }

  return $thawed
}

sub _read_core_cobalt_conf {
  my ($self) = @_;
  return $self->_read_conf("cobalt.conf");
}

sub _read_core_channels_conf {
  my ($self) = @_;
  return $self->_read_conf("channels.conf");
}

sub _read_core_plugins_conf {
  my ($self) = @_;
  return $self->_read_conf("plugins.conf");
}

sub _read_plugin_conf {
  ## read a conf for a specific plugin
  ## must be defined in plugins.conf when this method is called
  ## IMPORTANT: re-reads plugins.conf per call unless specified
  my ($self, $plugin, $plugins_conf) = @_;
  $plugins_conf = ref $plugins_conf eq 'HASH' ?
                  $plugins_conf
                  : $self->_read_core_plugins_conf ;

  ## at the moment we just go away quietly if there's no Config
  ## shouldfix; handle this when calling rather than here .. ?
  ## may be useful to be able to specify a config on an online load
  ## this is mostly to make _autoloads life easier
  if (!exists $plugins_conf->{$plugin} ||
      ! $plugins_conf->{$plugin}->{Config}) {
    ## no config entry for this plugin, do nothing quietly
    return
  }

  my $this_plug_cf = $self->_read_conf( $plugins_conf->{$plugin}->{Config} );
  unless ($this_plug_cf && ref $this_plug_cf eq 'HASH') {
    ## no luck, set empty hash
    $this_plug_cf = { };
  }

  ## we might still have Opts (PluginOpts) directive:
  if ( defined $plugins_conf->{$plugin}->{Opts} ) {
    ## copy to PluginOpts
    $this_plug_cf->{PluginOpts} = delete $plugins_conf->{Opts};
  }

  return $this_plug_cf
}

sub _autoload_plugin_confs {
  my $self = shift;
  my $plugincf = shift || $self->_read_core_plugins_conf;
  my $perpkgcf = { };

  for my $plugin_alias (keys %$plugincf) {
    ## core plugin_cf is keyed on __PACKAGE__ definitions:
    my $pkg = $plugincf->{$plugin_alias}->{Module};
    unless ($pkg) {
      carp "skipping $plugin_alias, no Module directive";
      next
    }
    $perpkgcf->{$pkg} = $self->_read_plugin_conf($plugin_alias, $plugincf);
  }

  return $perpkgcf
}


sub read_cfg {
  my ($self) = @_;
  my $conf = {};

  $conf->{path} = $self->{etc};
  $conf->{path_chan_cf} = $conf->{path} ."/channels.conf" ;
  $conf->{path_plugins_cf} = $conf->{path} . "/plugins.conf" ;

  my $core_cf = $self->_read_core_cobalt_conf;
  if ($core_cf && ref $core_cf eq 'HASH') {
    $conf->{core} = $core_cf;
  } else {
    croak "failed to load cobalt.conf";
  }

  my $chan_cf = $self->_read_core_channels_conf;
  if ($chan_cf && ref $chan_cf eq 'HASH') {
    $conf->{channels} = $chan_cf;
  } else {
    carp "failed to load channels.conf";
    ## busted cf, set up an empty context
    $conf->{channels} = { Main => {} } ;
  }

  my $plug_cf = $self->_read_core_plugins_conf;
  if ($plug_cf && ref $plug_cf eq 'HASH') {
    $conf->{plugins} = $plug_cf;
  } else {
    carp "failed to load plugins.conf";
    $conf->{plugins} = { } ;
  }

  if (scalar keys $conf->{plugins}) {
    $conf->{plugin_cf} = $self->_autoload_plugin_confs($conf->{plugins});
  }

  return $conf
}


1;
