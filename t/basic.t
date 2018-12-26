#!/usr/bin/env perl
use File::Basename qw(dirname);
use Cwd qw(realpath);
use File::Spec::Functions qw(catdir);

BEGIN {
  require lib;
  my $dir = dirname(dirname(realpath(__FILE__)));
  lib->import(catdir($dir, 'local', 'lib', 'perl5'), catdir($dir, 'lib'));
}

use Mojo::Base -strict, -signatures;
use Mojo::Collection qw(c);
use Test::More;

use ok 'BMO::Editor';
use ok 'BMO::Editor::Format';
use ok 'BMO::Editor::Item';
use ok 'BMO::Editor::Format::Milestone';

my $c = c(
  {value => 'mozilla66', sortkey => 10, active => 1, bugs => 0},
  {value => 'mozilla67', sortkey => 10, active => 0, bugs => 0},
);

{
  my $fmt  = BMO::Editor::Format::Milestone->new;
  my $line = $fmt->encode($c->[0]);
  my $item = $fmt->decode($line);
  is $item->id, 0, "check id starts at 0";
  is_deeply $item->content, {value => 'mozilla66', sortkey => 10, active => 1},
    "encode/decode roundtrips fields";
}

my $editor = BMO::Editor->new(
  invoke_editor => sub($lines) {
    $lines->grep(sub { /^id:0001/ })->map(sub { s/mozilla(\d+)/Firefox $1/grs });
  },
);
my ($items, $removed) = $editor->edit('Milestone', $c);

is $removed->size, 1, "check number of removed items";
is $removed->[0]->id, 0, "check id of removed item";
is_deeply $removed->[0]->content, $c->[0], "verify what was removed";
is $items->[0]->id, 1, "verify what was modified";
is $items->[0]->content->{value}, 'Firefox 67', "check value";

done_testing;
