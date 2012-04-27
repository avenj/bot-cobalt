package Bot::Cobalt::Frontend::Utils;

use 5.10.1;
use strictures 1;

use Carp;

use base 'Exporter';

our @EXPORT_OK = qw/
  ask_yesno
  ask_question
/;

sub ask_question {
  my %args = @_;
  
  my $question = $args{prompt} || croak "No prompt => specified";
  my $default  = $args{default};
  
  STDOUT->autoflush(1);
  
  my $input;
  
  my $print_and_grab = sub {
    print "$question ";
    if (defined $default) {
      print "[$default] ";
    } else {
      print "> ";
    }
    $input = <STDIN>;
    chomp($input);
    $input = $default if defined $default and $input eq '';
    $input
  };
  
  $print_and_grab->();
  
  until ($input) {
    print "No input specified.\n";
    $print_and_grab->();
  }
  
  return $input
}

sub ask_yesno {
  my %args = @_;
  
  my $question = $args{prompt} || croak "No prompt => specified";
  my $default  = lc(
    substr($args{default}||'', 0, 1) || croak "No default => specified"
  );
  croak "default should be Y or N"
    unless $default =~ /^[yn]$/;

  my $yn = $default eq 'y' ? 'Y/n' : 'y/N' ;
  
  STDOUT->autoflush(1);

  my $input;

  my $print_and_grab = sub {
    print "$question  [$yn] ";
    $input = <STDIN>;
    chomp($input);
    $input = $default if $input eq '';
    lc(substr $input, 0, 1);
  };

  $print_and_grab->();
   
  until ($input ~~ [qw/y n/]) {
    print "Invalid input; should be either Y or N\n";
    $print_and_grab->();
  }

  return $input eq 'y'
}

1;
