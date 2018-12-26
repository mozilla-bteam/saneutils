#!/usr/bin/env perl
use File::Basename qw(dirname);
use Cwd qw(realpath);
use File::Spec::Functions qw(catdir);

BEGIN {
  require lib;
  my $dir = dirname(realpath(__FILE__));
  lib->import(catdir($dir, 'local', 'lib', 'perl5'), catdir($dir, 'lib'));
}

use Mojo::Base -strict, -signatures;

use BMO::Editor;
use BMO::Tool;
use Data::Printer;
use List::Util qw(none);
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json);
use Mojo::URL;
use Mojo::UserAgent;
use Mojo::Util qw(getopt trim slugify html_attr_unescape);

getopt 'product=s' => \my $product;

my $tool       = BMO::Tool->new;
my $editor     = BMO::Editor->new();
my $milestones = $tool->get_milestones($product);
my ($items, $removed) = $editor->edit('Milestone', $milestones);

my $modified = $items->grep('is_modified')->first;
p $modified;

# $removed->with_roles('+ProgressBar')->each(
#   sub {
#     if ($_->content->{bugs}) {
#       warn "Cannot delete ", $_->content->{value}, " because it has bugs";
#       return;
#     }
#     $tool->delete_milestone($product, $_->content->{value});
#   });
