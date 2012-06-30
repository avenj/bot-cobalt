package Bot::Cobalt::Conf;
our $VERSION = '0.011';

## Bot::Cobalt::Conf
## Looks for the following YAML confs:
##   etc/cobalt.conf
##   etc/channels.conf
##   etc/plugins.conf
##
## Plguins can specify their own config files to load
## See plugins.conf for more information.

use 5.10.1;
use Moo;
use strictures 1;

use Carp;
use Try::Tiny;

use File::Spec;

use Bot::Cobalt::Common qw/:types/;
use Bot::Cobalt::Serializer;

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


sub _read_conf {
  ## deserialize a YAML conf
  my ($self, $relative_to_etc) = @_;

  confess "no path specified in _read_conf"
    unless defined $relative_to_etc;

  my $etc = $self->etc;

  warn "_read_conf; using etcdir $etc\n" if $self->debug;

  unless (-e $self->etc) {
    carp "cannot find etcdir: $self->etc";
    return
  }

  my $path = File::Spec->catfile(
    $etc,
    File::Spec->splitpath($relative_to_etc)
  );
  
  warn "_read_conf; reading conf path $path\n" if $self->debug;

  unless (-e $path) {
    carp "cannot find $path at $self->etc";
    return
  }

  my $serializer = Bot::Cobalt::Serializer->new;
  
  my $thawed;
  try
    { $thawed = $serializer->readfile( $path ) }
  catch {
    ## Still dies, but with more useful information.
    croak "Serializer readfile() failed for $path: $_"
  };

  unless ($thawed) {
    carp "Serializer returned nothing; empty file, perhaps? ($path)";
    return
  }

  return $thawed
}

sub _read_core_cobalt_conf {
  my ($self) = @_;
  my $thawed = $self->_read_conf("cobalt.conf");
  
  confess "Conf; cobalt.conf; no IRC configuration found"
    unless ref $thawed->{IRC} eq 'HASH'
    and keys %{ $thawed->{IRC} };

  warn "Conf; cobalt.conf; IRC->ServerAddr not specified\n"
    unless defined $thawed->{IRC}->{ServerAddr};
  
  return $thawed
}

sub _read_core_channels_conf {
  my ($self) = @_;
  
  my $thawed = $self->_read_conf("channels.conf");
  
  warn "Conf; channels.conf; did not find configured channels for Main\n"
    unless ref $thawed->{Main} eq 'HASH'
    and keys %{ $thawed->{Main} };

  CONTEXT: for my $context (keys %$thawed) {
    my $ctxt_cfg = $thawed->{$context};

    unless (ref $ctxt_cfg eq 'HASH') {
      confess 
        "Conf; channels.conf; cfg for context $context is not a hash";
    }

    CHAN: for my $channel (keys %$ctxt_cfg) {
      unless (ref $ctxt_cfg->{$channel} eq 'HASH') {
        warn "Conf; channels.conf; ",
          "cfg for $channel on $context is not a hash\n";
        $ctxt_cfg->{$channel} = {};
      }
    } ## CHAN
  
  }

  return $thawed
}

sub _read_core_plugins_conf {
  my ($self) = @_;
  my $thawed = $self->_read_conf("plugins.conf");
  
  my @accepted_keys = qw/
    Config
    Module
    NoAutoLoad
    Opts
    Priority
  /;
  
  warn "Conf; plugins.conf; no plugins found\n"
    unless keys %$thawed;
  
  for my $plugin (keys %$thawed) {
    my $this_plug_cf = $thawed->{$plugin};
    
    confess "Conf; plugins.conf; cfg for $plugin is not a hash"
      unless ref $this_plug_cf eq 'HASH';
    
    confess "Conf; plugins.conf; no Module directive for $plugin"
      unless $this_plug_cf->{Module};
    
    confess "Conf; plugins.conf; $plugin - Priority must be numeric"
      if defined $this_plug_cf->{Priority}
      and $this_plug_cf->{Priority} !~ /^\d+$/;

    confess "Conf; plugins.conf; $plugin - Opts must be a hash"
      if defined $this_plug_cf->{Opts}
      and ref $this_plug_cf->{Opts} ne 'HASH';

    for my $directive (keys %$this_plug_cf) {
      warn "Conf; plugins.conf; unknown directive $directive\n"
        unless $directive ~~ @accepted_keys;
    }
  }
  
  return $thawed
}

sub _read_plugin_conf {
  ## read a conf for a specific plugin
  ## must be defined in plugins.conf when this method is called
  my ($self, $plugin, $plugins_conf) = @_;

  ## re-reads plugins.conf per call unless specified:
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
    confess "Failed to load cobalt.conf";
  }

  my $chan_cf = $self->_read_core_channels_conf;
  if ($chan_cf && ref $chan_cf eq 'HASH') {
    $conf->{channels} = $chan_cf;
  } else {
    carp "Conf; Failed to load channels.conf, using empty hash";
    ## busted cf, set up an empty context
    $conf->{channels} = { Main => {} } ;
  }

  my $plug_cf = $self->_read_core_plugins_conf;
  if ($plug_cf && ref $plug_cf eq 'HASH') {
    $conf->{plugins} = $plug_cf;
  } else {
    carp "Conf; Failed to load plugins.conf, using empty hash";
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

Bot::Cobalt::Conf - Load Bot::Cobalt configuration files

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

=cut
