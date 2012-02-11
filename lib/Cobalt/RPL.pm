package Cobalt::RPL;
our $VERSION = '0.04';

## Object returned by $core->rpl_parser
##
## This is a RPL parser that automatically creates unknown methods 
## in other to provide syntax sugar via $core->rpl_parser:
##
##  my $parser = $core->rpl_parser;
##  $parser->varname($value);
##    .. etc ..
##  my $formatted = $parser->Format("SOME_RPL_KEY");
##
## The tradeoff, of course, is that the method cache is useless and 
## there is a performance penalty attached to magicking up methods . . .

use 5.12.1;
use strict;
use warnings;

use Cobalt::Utils qw/rplprintf/;

our $AUTOLOAD;

sub new {
  my $self = {};
  bless $self, shift;
  
  my %args = @_;
  
  my $langset = $args{Lang};
  unless ($langset && ref $langset eq 'HASH') {
    warn "Cobalt::RPL needs to be passed a langset via Lang\n";
    return
  }

  ## ugly self keys are because these aren't valid rplprintf vars:
  $self->{'%%LANG'} = $langset;
  
  return $self
}

sub Format {
  my ($self, $rpl) = @_;
  return unless $rpl;
  return "Missing/undef RPL: $rpl" unless $self->{'%%LANG'}->{$rpl};
  
  my $vars;
  for my $var (@{ $self->{'%%ADDED'} }) {
    $vars->{$var} = $self->$var();
  }  

  my $formatted = rplprintf( $self->{'%%LANG'}->{$rpl}, $vars );
  
  return $formatted
}

sub AUTOLOAD {
  ## magic method creation
  ## (after initialization this accessor sticks around)
  my $self = shift || return undef;
  
  my ($method) = $AUTOLOAD =~ m/::(.*)$/;
  return if $method eq 'DESTROY';

  push(@{ $self->{'%%ADDED'} }, $method);

  my $accessor = sub {
    my $this_self = shift;
    
    return $this_self->{$method} = shift
      if @_;
    return $this_self->{$method}
  };
  
  no strict 'refs';
  *$AUTOLOAD = $accessor;
  use strict;
  
  ## put $self back:
  unshift @_, $self;
  
  goto &$AUTOLOAD;
}

1;
