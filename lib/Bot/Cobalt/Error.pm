package Bot::Cobalt::Error;

use 5.12.1;
use strictures 1;

use overload
  '""'     => sub { shift->string },
  fallback => 1;

sub new {
  my $class = shift;
  bless [ @_ ], ref $class || $class
}

sub string {
  my ($self) = @_;
  join '', map { "$_" } @$self
}

sub push {
  my $self = shift;
  push @$self, @_;
  $self->new(@$self)
}

sub unshift {
  my $self = shift;
  unshift @$self, @_;
  $self->new(@$self)
}

sub join {
  my ($self, $delim) = @_;
  $delim //= ' ';
  $self->new( join($delim, map { "$_" } @$self) )
}


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Error - Lightweight error objects

=head1 SYNOPSIS

  package SomePackage;
  
  sub some_method {
    . . .
    
    die Bot::Cobalt::Error->new(
      "Some errors occured:",
      @errors
    )->join("\n");

    ## ... same as:
    die Bot::Cobalt::Error->new(
      "Some errors occured:\n",
      join("\n", @errors)
    );
  }
  
  
  package CallerPackage;
  
  use Try::Tiny;
  
  try {
    SomePackage->some_method();
  } catch {
    ## $error isa Bot::Cobalt::Error
    my $error = $_;
    
    ## Stringifies to the error string:
    warn "$error\n";
  };

=head1 DESCRIPTION

A lightweight exception object for L<Bot::Cobalt>.

B<new()> takes a list of messages used to compose an error string.

These objects stringify to the stored errors.

=head2 string

Returns the current error string; this is the same value returned when 
the object is stringified, such as:

  warn "$error\n";

=head2 join

  $error = $error->join("\n");

Returns a new object whose only element is the result of joining the 
stored list of errors with the specified expression.

Defaults to joining with a single space. Does not modify the existing 
object.

=head2 push

  $error = $error->push(@errors);

Appends the specified list to the existing array of errors.

Modifies the existing object and also returns a new object.

=head2 unshift

  $error = $error->unshift(@errors);

Prepends the specified list to the existing array of errors.

Modifies the existing object and also returns a new object.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
