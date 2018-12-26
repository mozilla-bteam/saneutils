#!/usr/bin/env perl
use File::Basename qw(dirname);
use Cwd qw(realpath);
use File::Spec::Functions qw(catdir);

BEGIN {
  require lib;
  my $dir = dirname(dirname(realpath(__FILE__)));
  lib->import(catdir($dir, 'local', 'lib', 'perl5'), catdir($dir, 'lib'));
}

use Mojo::Collection qw(c);
use Test::More;

my $c = c(
    { name => 'Bob',   sortkey => 1000 },
    { name => 'Ted',   sortkey => 3000 },
    { name => 'Alice', sortkey => 2000 },
    { name => 'Chuck', sortkey => 4000 },
    { name => 'New' }
);


done_testing;
