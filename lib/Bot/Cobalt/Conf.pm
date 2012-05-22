package Bot::Cobalt::Conf;
our $VERSION = '0.003';

## Bot::Cobalt::Conf
## Looks for the following YAML confs:
##   etc/cobalt.conf
##   etc/channels.conf
##   etc/plugins.conf
##
## Plguins can specify their own config files to load
## See plugins.conf for more information.

use 5.10.1;
use strict;
use warnings;
use Carp;

use Moo;
use Bot::Cobalt::Common qw/:types/;

use File::Spec;

has 'etc' => ( is => 'rw', isa => Str, required => 1 );

use Bot::Cobalt::Serializer;

sub _read_conf {
  ## deserialize a YAML conf
  my ($self, $relative_to_etc) = @_;

  unless ($relative_to_etc) {
    carp "no path specified in _read_conf?";
    return
  }

  my $etc = $self->etc;
  unless (-e $self->etc) {
    carp "cannot find etcdir: $self->etc";
    return
  }

  my $path = File::Spec->catfile(
    $etc,
    File::Spec->splitpath($relative_to_etc)
  );

  unless (-e $path) {
    carp "cannot find $path at $self->etc";
    return
  }

  my $serializer = Bot::Cobalt::Serializer->new;
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

  return unless exists $plugins_conf->{$plugin};

  my $this_plug_cf = { };
  if ( $plugins_conf->{$plugin}->{Config} ) {
    $this_plug_cf = 
      $self->_read_conf( $plugins_conf->{$plugin}->{Config} ) || {};
  }

  ## we might still have Opts (PluginOpts) directive:
  if ( defined $plugins_conf->{$plugin}->{Opts} ) {
    ## copy to PluginOpts
    $this_plug_cf->{PluginOpts} = delete $plugins_conf->{$plugin}->{Opts};
  }

  return $this_plug_cf
}

sub _autoload_plugin_confs {
  my $self = shift;
  my $plugincf = shift || $self->_read_core_plugins_conf;
  my $per_alias_cf = { };

  for my $plugin_alias (keys %$plugincf) {
    my $pkg = $plugincf->{$plugin_alias}->{Module};
    unless ($pkg) {
      carp "skipping $plugin_alias, no Module directive";
      next
    }
    $per_alias_cf->{$plugin_alias} = $self->_read_plugin_conf($plugin_alias, $plugincf);
  }

  return $per_alias_cf
}


sub read_cfg {
  my ($self) = @_;
  my $conf = {};

  $conf->{path} = $self->etc;
  $conf->{path_chan_cf} = File::Spec->catfile( 
    $conf->{path}, "channels.conf"
  );
  $conf->{path_plugins_cf} = File::Spec->catfile(
    $conf->{path}, "plugins.conf"
  );

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

  if (scalar keys %{ $conf->{plugins} }) {
    $conf->{plugin_cf} = $self->_autoload_plugin_confs($conf->{plugins});
  }

  return $conf
}


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Conf - Parse Cobalt configuration files

=head1 SYNOPSIS

  ## Load:
  ##  - cobalt.conf
  ##  - channels.conf
  ##  - plugins.conf
  ##  - configured plugin-specific confs
  my $cfg_obj = Bot::Cobalt::Conf->new(
    etc => $path_to_etc_dir
  );
  
  my $cfg_hash = $cfg_obj->read_cfg;

=head1 DESCRIPTION

Normally used by frontends to create a configuration hash to pass to 
L<Bot::Cobalt::Core>'s constructor.

Loads Cobalt configuration files from a directory (specified via B<etc> 
at construction) and produces a hash with the following keys:

=head2 core

Loaded from C<cobalt.conf>

The core Cobalt configuration.

=head2 channels

Loaded from C<channels.conf>

Configured context and channel settings.

Keyed on context name. Per-context hash is keyed on channel name.

=head2 plugins

Loaded from C<plugins.conf>

Configured plugins. Keyed on plugin alias.

=head2 plugin_cf

Per-plugin options loaded from either B<PluginOpts> directives in 
C<plugins.conf> or plugin-specific configuration files included via 
B<Config> directives. Keyed on plugin alias.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
