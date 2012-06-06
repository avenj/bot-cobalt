package Bot::Cobalt::Serializer;
our $VERSION = '0.007';

use 5.10.1;
use strictures 1;

use Moo;
use Carp;

## These two must be present anyway:
use YAML::XS ();
use JSON ();

use Bot::Cobalt::Common qw/:types/;

use Fcntl qw/:flock/;

has 'Format' => ( is => 'rw', isa => Str,
  default => sub { 'YAMLXS' },
  trigger => sub {
    my ($self, $format) = @_;

    $format = uc($format);

    croak "Unknown format $format"
      unless $format ~~ [ keys %{ $self->Types } ];

    croak "Requested format $format but can't find a module for it"
      unless $self->_check_if_avail($format)
  },
);

has 'Types' => ( is => 'ro', isa => HashRef, lazy => 1,
  default => sub {
    {
      YAML   => 'YAML::Syck',
      YAMLXS => 'YAML::XS',
      JSON   => 'JSON',
      XML    => 'XML::Dumper',
    }
  },
);

has 'Logger' => ( is => 'rw', isa => Object,
  trigger => sub {
    my ($self, $logobj) = @_;
    my $method = $self->LogMethod;

    die "Logger specified but method $method not found"
      unless $logobj->can($method);
  },
);

has 'LogMethod' => ( is => 'rw', isa => Str, lazy => 1,
  default => sub { 'error' },
);


has 'yamlxs_from_ref' => ( is => 'rw', lazy => 1,
  coerce => sub {
    YAML::XS::Dump($_[0])
  },
);

has 'ref_from_yamlxs' => ( is => 'rw', lazy => 1,
  coerce => sub {
    YAML::XS::Load($_[0])
  },
);

has 'yaml_from_ref' => ( is => 'rw', lazy => 1,
  coerce => sub {
    require YAML::Syck;
    YAML::Syck::Dump($_[0])
  },
);

has 'ref_from_yaml' => ( is => 'rw', lazy => 1,
  coerce => sub {
    require YAML::Syck;
    YAML::Syck::Load($_[0])
  },
);

has 'json_from_ref' => ( is => 'rw', lazy => 1,
  coerce => sub {
    my $jsify = JSON->new->allow_nonref;
    $jsify->utf8->encode($_[0]);
  },
);

has 'ref_from_json' => ( is => 'rw', lazy => 1,
  coerce => sub {
    my $jsify = JSON->new->allow_nonref;
    $jsify->utf8->decode($_[0])
  },
);

has 'xml_from_ref' => ( is => 'rw', lazy => 1,
  coerce => sub {
    require XML::Dumper;
    XML::Dumper->new->pl2xml($_[0])
  },
);

has 'ref_from_xml' => ( is => 'rw', lazy => 1,
  coerce => sub {
    require XML::Dumper;
    XML::Dumper->new->xml2pl($_[0])
  },
);

sub BUILDARGS {
  my ($class, @args) = @_;
  ## my $serializer = Bot::Cobalt::Serializer->new( %opts )
  ## Serialize to YAML using YAML::XS:
  ## ->new()
  ## - or -
  ## ->new($format)
  ## ->new('JSON')  # f.ex
  ## - or -
  ## ->new( Format => 'JSON' )   ## --> to JSON
  ## - or -
  ## ->new( Format => 'YAML' ) ## --> to YAML1.0
  ## - and / or -
  ## Specify something with a LogMethod method, default 'error':
  ## ->new( Logger => $core->log );
  ## ->new( Logger => $core->log, LogMethod => 'crit' );
  
  if (@args == 1) {
    return { Format => shift @args }
  } else {
    return { @args }
  }
}

sub freeze {
  ## ->freeze($ref)
  ## serialize arbitrary data structure
  my ($self, $ref) = @_;
  unless (defined $ref) {
    carp "freeze() received no data";
    return
  }

  my $method = lc( $self->Format );
  $method = $method . "_from_ref";
  return $self->$method($ref);
}

sub thaw {
  ## ->thaw($data)
  ## deserialize data in specified Format
  my ($self, $data) = @_;
  unless (defined $data) {
    carp "thaw() received no data";
    return
  }

  my $method = lc( $self->Format );
  $method = "ref_from_" . $method ;
  return $self->$method($data);
}

sub writefile {
  my ($self, $path, $ref, $opts) = @_;
  ## $serializer->writefile($path, $ref [, { Opts });
  ## serialize arbitrary data and write it to disk
  if      (!$path) {
    $self->_log("writefile called without path argument");
    return
  } elsif (!defined $ref) {
    $self->_log("writefile called with nothing to write");
    return
  }
  my $frozen = $self->freeze($ref);
  $self->_write_serialized($path, $frozen, $opts); 
}

sub readfile {
  my ($self, $path, $opts) = @_;
  ## my $ref = $serializer->readfile($path)
  ## thaw a file into data structure
  if (!$path) {
    $self->_log("readfile called without path argument");
    return
  } elsif (!-r $path || -d $path ) {
    $self->_log("readfile called on unreadable file $path");
    return
  }
  my $data = $self->_read_serialized($path, $opts);
  return $self->thaw($data);
}

sub version {
  my ($self) = @_;
  my $module = $self->Types->{ $self->Format };
  { local $@; eval "require $module" }
  return($module, $module->VERSION);
}

## Internals

sub _log {
  my ($self, $message) = @_;
  my $method = $self->LogMethod;
  unless ($self->Logger && $self->Logger->can($method) ) {
    carp "$message\n";
  } else {
    $self->Logger->$method($message);
  }
}


sub _check_if_avail {
  my ($self, $type) = @_;
  ## see if we have this serialization method available to us
  my $module;
  return unless $module = $self->Types->{$type};
  eval "require $module";
  if ($@) {
    $self->_log("$type specified but $module not available");
    return
  } else {
    return $module
  }
}


sub _read_serialized {
  my ($self, $path, $opts) = @_;
  return unless $path;
  if (-d $path || ! -e $path) {
    $self->_log("file not readable: $path");
    return
  }

  my $lock = 1;
  if (defined $opts && ref $opts eq 'HASH') {
    $lock = $opts->{Locking} if defined $opts->{Locking};
  }

  open(my $in_fh, '<', $path)
    or $self->_log("open failed for $path: $!") and return;
  
  if ($lock) {
    flock($in_fh, LOCK_SH)  # blocking call
      or $self->_log("LOCK_SH failed for $path: $!") and return;
   }

  my $data = join('', <$in_fh>);

  if ($lock) {
    flock($in_fh, LOCK_UN)
      or $self->_log("LOCK_UN failed for $path: $!");
  }

  close($in_fh)
    or $self->_log("close failed for $path: $!");

  utf8::encode($data);

  return $data
}

sub _write_serialized {
  my ($self, $path, $data, $opts) = @_;
  return unless $path and defined $data;

  my $lock = 1;
  if (defined $opts && ref $opts eq 'HASH') {
    $lock = $opts->{Locking} if defined $opts->{Locking};
  }
  
  utf8::decode($data);

  open(my $out_fh, '>>', $path)
    or $self->_log("open failed for $path: $!") and return;

  if ($lock) {
    flock($out_fh, LOCK_EX | LOCK_NB)
      or $self->_log("LOCK_EX failed for $path: $!") and return;
  }

  seek($out_fh, 0, 0)
    or $self->_log("seek failed for $path: $!") and return;
  truncate($out_fh, 0)
    or $self->_log("truncate failed for $path") and return;

  print $out_fh $data;

  if ($lock) {
    flock($out_fh, LOCK_UN)
      or $self->_log("LOCK_UN failed for $path: $!");
  }

  close($out_fh)
    or $self->_log("close failed for $path: $!");

  return 1
}

1;

__END__

=pod

=head1 NAME

Bot::Cobalt::Serializer - Simple serialization wrapper

=head1 SYNOPSIS

  use Bot::Cobalt::Serializer;

  ## Spawn a YAML1.0 handler:
  my $serializer = Bot::Cobalt::Serializer->new;

  ## Spawn a JSON handler
  my $serializer = Bot::Cobalt::Serializer->new('JSON');
  ## ...same as:
  my $serializer = Bot::Cobalt::Serializer->new( Format => 'JSON' );

  ## Spawn a YAML1.1 handler that logs to $core->log->crit:
  my $serializer = Bot::Cobalt::Serializer->new(
    Format => 'YAMLXS',
    Logger => $core->log,
    LogMethod => 'crit',
  );

  ## Serialize some data to our Format:
  my $ref = { Stuff => { Things => [ 'a', 'b'] } };
  my $frozen = $serializer->freeze( $ref );

  ## Turn it back into a Perl data structure:
  my $thawed = $serializer->thaw( $frozen );

  ## Serialize some $ref to a file at $path
  ## The file will be overwritten
  ## Returns false on failure
  $serializer->writefile( $path, $ref );

  ## Do the same thing, but without locking
  $serializer->writefile( $path, $ref, { Locking => 0 } );

  ## Turn a serialized file back into a $ref
  ## Boolean false on failure
  my $ref = $serializer->readfile( $path );

  ## Do the same thing, but without locking
  my $ref = $serializer->readfile( $path, { Locking => 0 } );


=head1 DESCRIPTION

Various pieces of L<Bot::Cobalt> need to read and write serialized data 
from/to disk.

This simple OO frontend makes it trivially easy to work with a selection of 
serialization formats, automatically enabling Unicode encode/decode and 
optionally providing the ability to read/write files directly.


=head1 METHODS

=head2 new

  my $serializer = Bot::Cobalt::Serializer->new;
  my $serializer = Bot::Cobalt::Serializer->new( $format );
  my $serializer = Bot::Cobalt::Serializer->new( %opts );

Spawn a serializer instance. Will croak if you are missing the relevant 
serializer module; see L</Format>, below.

The default is to spawn a B<YAML::XS> (YAML1.1) serializer with error 
logging to C<carp>.

You can spawn an instance using a different Format by passing a simple 
scalar argument:

  $handle_syck = Bot::Cobalt::Serializer->new('YAML');
  $handle_yaml = Bot::Cobalt::Serializer->new('YAMLXS');
  $handle_json = Bot::Cobalt::Serializer->new('JSON');

Alternately, any combination of the following B<%opts> may be specified:

  $serializer = Bot::Cobalt::Serializer->new(
    Format =>
    Logger =>
    LogMethod =>
  );

See below for descriptions.

=head3 Format

Specify an input and output serialization format; this determines the 
serialization method used by L</writefile>, L</readfile>, L</thaw>, and 
L</freeze> methods. (You can change formats on the fly by calling 
B<Format> as a method.)

Currently available formats are:

=over

=item *

B<YAML> - YAML1.0 via L<YAML::Syck>

=item *

B<YAMLXS> - YAML1.1 via L<YAML::XS>  I<(default)>

=item *

B<JSON> - JSON via L<JSON::XS> or L<JSON::PP>

=item *

B<XML> - XML via L<XML::Dumper> I<(glacially slow)>

=back

The default is YAML I<(YAML Ain't Markup Language)> 1.1 (B<YAMLXS>)

YAML is very powerful, and the appearance of the output makes it easy for 
humans to read and edit.

JSON is a more simplistic format, often more suited for network transmission 
and talking to other networked apps. JSON is B<a lot faster> than YAML
(assuming L<JSON::XS> is available).
It also has the benefit of being included in the Perl core as of perl-5.14.

=head3 Logger

By default, all error output is delivered via C<carp>.

If you're not writing a B<Cobalt> plugin, you can likely stop reading right 
there; that'll do for the general case, and your module or application can 
worry about STDERR.

However, if you'd like, you can log error messages via a specified object's 
interface to a logging mechanism.

B<Logger> is used to specify an object that has a logging method of some 
sort.

That is to say:

  ## In a typical cobalt2 plugin . . . 
  ## assumes $core has already been set to the Cobalt core object
  ## $core provides the ->log attribute containing a Log::Handler:
  my $serializer = Bot::Cobalt::Serializer->new( Logger => $core->log );
  ## now errors will go to $core->log->$LogMethod()
  ## (log->error() by default)

  ##
  ## Meanwhile, in a stand-alone app or module . . .
  ##
  sub configure_logger {
    . . .
    ## Pick your poison ... Set up whatever logger you like
    ## Log::Handler, Log::Log4perl, Log::Log4perl::Tiny, Log::Tiny, 
    ## perhaps a custom job, whatever ...
    ## The only real requirement is that it have an OO interface
  }

  sub do_some_work {
    ## Typically, a complete logging module provides a mechanism for 
    ## easy retrieval of the log obj, such as get_logger
    ## (otherwise keeping track of it is up to you)
    my $log_obj = Log::Log4perl->get_logger('My.Logger');

    my $serializer = Bot::Cobalt::Serializer->new( Logger => $log_obj );
    ## Now errors are logged as: $log_obj->error($err)
    . . .
  }


Also see the L</LogMethod> directive.

=head3 LogMethod

When using a L</Logger>, you can specify LogMethod to change which log
method is called (typically the priority/verbosity level). 

  ## A slightly lower priority logger:
  my $serializer = Bot::Cobalt::Serializer->new(
    Logger => $core,
    LogMethod => 'warn',
  );

  ## A module using a Log::Tiny logger:
  my $serializer = Bot::Cobalt::Serializer->new(
    Logger => $self->{logger_object},
    ## Log::Tiny expects uppercase log methods:
    LogMethod => 'ERROR',
  );


Defaults to B<error>, which should work for at least L<Log::Handler>, 
L<Log::Log4perl>, and L<Log::Log4perl::Tiny>.


=head2 freeze

Turn the specified reference I<$ref> into the configured B<Format>.

  my $frozen = $serializer->freeze($ref);


Upon success returns a scalar containing the serialized format, suitable for 
saving to disk, transmission, etc.


=head2 thaw

Turn the specified serialized data (stored in a scalar) back into a Perl 
data structure.

  my $ref = $serializer->thaw($data);


(Try L<Data::Dumper> if you're not sure what your data actually looks like.)



=head2 writefile

L</freeze> the specified C<$ref> and write the serialized data to C<$path>

  print "failed!" unless $serializer->writefile($path, $ref);

Will fail with errors if $path is not writable for whatever reason; finding 
out if your destination path is writable is up to you.

Locks the file by default. You can turn this behavior off:

  $serializer->writefile($path, $ref, { Locking => 0 });

B<IMPORTANT:>
Uses B<flock> to lock the file for writing; the call is non-blocking, therefore 
writing to an already-locked file will fail with errors rather than waiting.

Will be false on apparent failure, probably with some carping.


=head2 readfile

Read the serialized file at the specified C<$path> (if possible) and 
L</thaw> the data structures back into a reference.

  my $ref = $serializer->readfile($path);

By default, attempts to gain a shared (LOCK_SH) lock on the file.
You can turn this behavior off:

  $serializer->readfile($path, { Locking => 0 });

B<IMPORTANT:>
This is not a non-blocking lock. C<readfile> will block until a lock is 
gained (to prevent data structures from "running dry" in between writes).
This is the opposite of what L</writefile> does, the general concept being 
that preserving the data existing on disk takes priority.
Turn off B<Locking> if this is not the behavior you want.

Will fail with errors if $path cannot be found or is unreadable.

If the file is malformed or not of the expected L</Format> the parser will 
whine at you.


=head2 version

Obtains the backend serializer and its VERSION for the current instance.

  my ($module, $modvers) = $serializer->version;

Returns a list of two values: the module name and its version.

  ## via Devel::REPL:
  $ Bot::Cobalt::Serializer->new->version
  $VAR1 = 'YAML::Syck';
  $VAR2 = 1.19;


=head1 SEE ALSO

=over

=item *

L<YAML::Syck> -- YAML1.0: L<http://yaml.org/spec/1.0/>

=item *

L<YAML::XS> -- YAML1.1: L<http://yaml.org/spec/1.1/>

=item *

L<JSON>, L<JSON::XS> -- JSON: L<http://www.json.org/>

=item *

L<XML::Dumper>

=back


=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>


=cut
