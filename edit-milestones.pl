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
my $milestones = $tool->get_milestones($product);
my ($items, $removed) = $editor->edit('Milestone', $milestones);
my $new      = $items->grep('is_new');
my $modified = $items->grep('is_modified');

$new->with_roles('+ProgressBar')->each(
  sub ($item, $i) {
    my $new = $item->content;
    $tool->add_milestone($product, $new->{value}, $new->{sortkey});
    unless ($new->{active}) {
      $tool->edit_milestone($product, $new->{value}, sub { $_->{isactive} = 0 });
    }
  }
);

$modified->with_roles('+ProgressBar')->each(
  sub ($item, $i) {
    my $old = $milestones->[$item->id];
    my $new = $item->content;
    my %update;
    if ($old->{value} ne $new->{value} && $old->{bugs}) {
      $tool->add_milestone($product, $new->{value}, $old->{sortkey});
      $tool->move_milestones($product, $old, $new->{value});
      $tool->delete_milestone($product, $old->{value});
      $old->{value} = $new->{value};
      $old->{active} = 1;
    }
    elsif ($old->{value} ne $new->{value}) {
      $update{milestone} = $new->{value};
    }
    if ($old->{active} xor $new->{active}) {
      $update{isactive} = $new->{active};
    }
    if ($old->{sortkey} != $new->{sortkey}) {
      $update{sortkey} = $new->{sortkey};
    }
    if (keys %update) {
      $tool->edit_milestone(
        $product,
        $old->{value},
        sub($input) {
          foreach my $key (keys %update) {
            $input->{$key} = $update{$key};
          }
        }
      );
    }
  }, 'Update Milestones'
);
say "Done.";
$removed->with_roles('+ProgressBar')->each(
  sub ($item, $i) {
    if ($item->content->{bugs}) {
      warn "Cannot delete ", $item->content->{value}, " because it has bugs";
      return;
    }
    $tool->delete_milestone($product, $item->content->{value});
  }, 'Remove Milestones'
);
say "Done.";
