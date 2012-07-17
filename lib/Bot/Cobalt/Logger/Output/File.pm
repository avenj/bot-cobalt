package Bot::Cobalt::Logger::Output::File;

use 5.12.1;
use strictures 1;

use Carp;

use Fcntl qw/:flock/;

sub PATH   () { 0 }
sub HANDLE () { 1 }

sub new {
  my $class = shift;

  my $self = [ 
    '',    ## PATH
    undef  ## HANDLE
  ];

  bless $self, $class;
  
  my %args = @_;
  $args{lc $_} = delete $args{$_} for keys %args;

  confess "new() requires a 'file' argument"
    unless defined $args{file};

  $self->file( $args{file} );

  $self
}

sub file {
  my ($self, $file) = @_;

  if (defined $file) {
    $self->_close if $self->_is_open;
    
    $self->[PATH] = $file
  }

  $self->[PATH]
}

sub _open {
  my ($self) = @_;
  
  return if $self->_is_open;

  open my $fh, '+<:encoding(UTF-8)', $self->file
    or croak "Log file could not be opened: ",
             join ' ', $self->file, $!;
  
  $self->[HANDLE] = $fh
}

sub _close {
  my ($self) = @_;
  
  return unless $self->_is_open;
  
  close $self->[HANDLE];

  $self->[HANDLE] = undef;

  1
}

sub _is_open {
  my ($self) = @_;
  
  $self->[HANDLE]
}

sub _write {
  my ($self, $str) = @_;
  
  $self->_open;

  ## FIXME if flock fails, buffer and try next _write up to X items ?
  ## FIXME maybe we should just fail silently (and document same)?
  flock($self->[HANDLE], LOCK_EX)
    or warn "flock failure for ".$self->file
    and $self->_close and return;

  print { $self->[HANDLE] } $str;

  flock($self->[HANDLE], LOCK_UN);
  
  $self->_close;

  1
}


1;
__END__
