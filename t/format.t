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
use Mojo::Collection;
use Test::More;

use ok 'BMO::Editor::Format::JSON';

my $format = BMO::Editor::Format::JSON->new();
my $content = {name => 'Bender', age => 27};

my $line = $format->encode($content);
my $item = $format->decode($line);
is $item->id, 0, "item id";
is $item->content->{name}, 'Bender', "item name";
is $item->content->{age},  27,       "item age";

ok !$item->is_new,      "not new";
ok !$item->is_modified, "not modified";

$line =~ s/Bender/Flexo/gs;
$item = $format->decode($line);
is $item->id, 0, "item id";
is $item->content->{name}, 'Flexo', "item name";
is $item->content->{age},  27,      "item age";

ok !$item->is_new, "still not new";
ok $item->is_modified, "item was modified";

done_testing;
