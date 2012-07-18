use Test::More tests => 13;
use Test::Exception;

use strict; use warnings;

use File::Spec;
use Try::Tiny;
use Module::Build;

my $this_class = 'Bot::Cobalt::Logger::Output';

my $basedir = try {
  Module::Build->current->base_dir
} catch {
  die "\nFailed to retrieve base_dir() from Module::Build\n",
    "are you trying to run the test suite outside of `./Build`?\n"
};

my $vardir = File::Spec->catdir( $basedir, 'var' );
my $test_log_path = File::Spec->catfile( $vardir, 'testing.log' );

use_ok( $this_class );

my $output = new_ok( $this_class );

ok( $output->time_format, 'has time_format' );
ok( $output->log_format,  'has log_format' );

dies_ok( sub { $output->add }, "add() dies with no args" );
dies_ok( sub { $output->add(1) }, "add() dies with odd args" );

ok( 
  $output->add(
    myfile => {
      type => 'File',
      file => $test_log_path,
    },
    
    myterm => {
      type => 'Term',
    },
  ),
  'add() file and term'
);

my $stdout;
{
  local *STDOUT;
  open STDOUT, '>', \$stdout
    or die "Could not reopen STDOUT: $!";

  ok( 
    $output->_write('info', [caller(0)], "Testing", "things"), 
    '_write()' 
  );

  close STDOUT
}

ok( $stdout, "Logged to STDOUT" );

ok( 
  do { local (@ARGV, $/) = $test_log_path; <> }, 
  "Logged to File"
);

## FIXME test with modified time_format / log_format ?

unlink $test_log_path;

my $tobj;
ok( $tobj = $output->get('myterm'), 'get()' );
isa_ok( $tobj, 'Bot::Cobalt::Logger::Output::Term' );

cmp_ok( $output->del('myterm', 'myfile'), '==', 2, 'del() 2 objects' );
