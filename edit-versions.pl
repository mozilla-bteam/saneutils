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
use Set::Object qw(set);

getopt 'product=s' => \my $product,
       'urlbase=s' => \$ENV{BMO_URLBASE};

my $tool       = BMO::Tool->new;
my $editor     = BMO::Editor->new();
my $versions = $tool->get_versions($product);
my ($items, $removed) = $editor->edit('Version', $versions);
my $new      = $items->grep('is_new');
my $modified = $items->grep('is_modified');

$new->with_roles('+ProgressBar')->each(
  sub ($item, $i) {
    my $new = $item->content;
    $tool->add_version($product, $new->{value});
    unless ($new->{active}) {
      $tool->edit_version($product, $new->{value}, sub { $_->{isactive} = 0 });
    }
  }, 'Add Versions'
);

$modified->with_roles('+ProgressBar')->each(
  sub ($item, $i) {
    my $old = $versions->[$item->id];
    my $new = $item->content;
    my %update;
    if ($old->{value} ne $new->{value} && $old->{bugs}) {
      $tool->add_version($product, $new->{value});
      $tool->move_versions($product, $old, $new->{value});
      $tool->delete_version($product, $old->{value});
      $old->{value} = $new->{value};
      $old->{active} = 1;
    }
    elsif ($old->{value} ne $new->{value}) {
      $update{version} = $new->{value};
    }
    if ($old->{active} xor $new->{active}) {
      $update{isactive} = $new->{active};
    }
    if (keys %update) {
      $tool->edit_version(
        $product,
        $old->{value},
        sub($input) {
          foreach my $key (keys %update) {
            $input->{$key} = $update{$key};
          }
        }
      );
    }
  }, 'Update Versions'
);
$removed->with_roles('+ProgressBar')->each(
  sub ($item, $i) {
    if ($item->content->{bugs}) {
      warn "Cannot delete ", $item->content->{value}, " because it has bugs";
      return;
    }
    $tool->delete_version($product, $item->content->{value});
  }, 'Remove Versions'
);

say "Requests made: ", $tool->browse_counter;
