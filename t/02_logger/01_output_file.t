use Test::More tests => 11;
use Test::Exception;

use strict; use warnings;

use File::Spec;
use Try::Tiny;
use Module::Build;

my $this_class = 'Bot::Cobalt::Logger::Output::File';

my $basedir = try {
  Module::Build->current->base_dir
} catch {
  BAIL_OUT("Failed to retrieve base_dir() from Module::Build; ".
    "are you trying to run the test suite outside of `./Build`?")
};

my $vardir = File::Spec->catdir( $basedir, 'var' );
my $test_log_path = File::Spec->catfile( $vardir, 'testing.log' );

use_ok( $this_class );

dies_ok( sub { $this_class->new }, 'new() with no args dies' );

my $output = new_ok( $this_class => [
    file => $test_log_path,
  ],
);

is( $output->file, $test_log_path, 'file() returns log path' );

is( $output->perms, 0666, 'perms() returned 0666' );

ok( $output->_write("This is a test string"), '_write()' );

ok( -e $test_log_path, 'Log file was created' );

my $contents = do { local (@ARGV, $/) = $test_log_path ; <> };

chomp $contents;
cmp_ok( $contents, 'eq', "This is a test string" );

## FIXME test mode / perms ?

unlink $test_log_path;

ok( 
  $output->_write("Testing against fresh log"), 
  '_write() after unlink()' 
);

ok( -e $test_log_path, 'Log file was recreated' );

$contents = do { local (@ARGV, $/) = $test_log_path ; <> };
chomp $contents;
cmp_ok( $contents, 'eq', "Testing against fresh log" );

unlink $test_log_path;
