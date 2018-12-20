#!/usr/bin/env perl
use 5.28.0;
use experimental 'signatures';
use File::Basename qw(dirname);
use Cwd qw(realpath);
use File::Spec::Functions qw(catdir);

BEGIN {
  require lib;
  lib->import(catdir(dirname(realpath(__FILE__)), 'local', 'lib', 'perl5'));
}

use Mojo::UserAgent;
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json);
use Mojo::Util qw(getopt trim slugify html_attr_unescape);
use Mojo::URL;
use List::Util qw(all);
use Proc::InvokeEditor;
use Set::Object qw(set);
use Term::ProgressBar;
use Data::Printer;

my $ua      = Mojo::UserAgent->new();
my $file    = path("config.json");
my $config  = decode_json($file->slurp);
my $urlbase = Mojo::URL->new($config->{urlbase});
my $cookies = $config->{cookies}{$urlbase->host};

$ua->cookie_jar->ignore(sub {0});
$ua->cookie_jar->add(
  map {
    Mojo::Cookie::Response->new(
      name     => $_,
      value    => $cookies->{$_},
      domain   => $urlbase->host,
      secure   => 1,
      httponly => 1,
      path     => '/',
      )
  } keys %$cookies
);

getopt 'product=s' => \my $product;

if (1) {
  my @milestones = get_milestones($ua, $urlbase, $product)->@*;
  my $id         = 0;
  my @unedited   = map {
    join(" ",
      sprintf("%.4x", $id++),
      $_->{active} ? '[x]' : '[_]',
      $_->{bugs},
      $_->{value}
    )
  } @milestones;
  my @edited = Proc::InvokeEditor->edit(\@unedited, '.txt');

  my $unedited_ids = set(map {/^([[:xdigit:]]{4})/} @unedited);
  my $edited_ids   = set(map {/^([[:xdigit:]]{4})/} @edited);

  my @to_delete = map { hex($_) } ($unedited_ids - $edited_ids)->members;

  warn "nothing to delete\n" unless @to_delete;
  {
    my $max = @to_delete;
    my $progress = Term::ProgressBar->new(
      {name => 'Delete', count => $max, remove => 1, ETA => 'linear'});
    my $next_update = 0;
    foreach my $milestone (@milestones[@to_delete]) {
      if ($milestone->{bugs}) {
        warn "Cannot delete $milestone->{value} because it has bugs\n";
        next;
      }
      delete_milestone($ua, $milestone->{delete_url}) if $milestone->{delete_url};
      $next_update = $progress->update($_) if $_ >= $next_update;
    }
    $progress->update($max) if $max >= $next_update;
  }

  # find renames and active/inactive status
  my %checkbox_to_bool = ('[x]' => 1, '[_]' => 0);
  foreach my $edit (@edited) {
    my ($id, $checkbox, $bugs, $value) = split(/\s+/, $edit, 4);
    my $active = $checkbox_to_bool{$checkbox};
    my $milestone = $milestones[ hex($id) ];
    die "No milestone with id $id" unless defined $milestone;
    die "invalid checkbox value: $checkbox" unless defined $active;

    my %update;
    if (trim($milestone->{value}) ne trim($value)) {
      $update{milestone} = $value;
    }
    if ($milestone->{active} xor $active) {
      $update{isactive} = $active;
    }
    if (keys %update && $milestone->{edit_url}) {
      if ($milestone->{bugs}) {
        warn "Cannot edit $milestone->{value}, because it has bugs associated.\n";
        next;
      }
      edit_milestone($ua, $milestone->{edit_url}, \%update);
    }
  }

}

sub extract_href ($urlbase, $dom) {
  my $link = $dom->at('a[href]');
  if ($link) {
    my $url = Mojo::URL->new(html_attr_unescape $link->attr('href'));
    $url->host($urlbase->host);
    $url->scheme('https');
  }
  else {
    return undef;
  }
}

sub edit_milestone ($ua, $url, $update) {
  my $resp      = $ua->get($url)->result;
  my $dom       = $resp->dom;
  my $product   = $url->query->param('product');
  my $milestone = $url->query->param('milestone');
  check_title($dom, qq{Edit Milestone '$milestone' of product '$product'});

  my $form = $dom->at('form[action*="/editmilestones.cgi"]') or die "cannot find form";
  my %input = ( extract_inputs($form->find('input'))->@*, %$update );

  my $action = html_attr_unescape $form->attr('action');
  my $form_url = $url->clone;
  $form_url->path($action);
  $form_url->query(Mojo::Parameters->new);

  my $post_resp = $ua->post($form_url, form => \%input)->result;
  my $post_dom = $post_resp->dom;
  check_title($post_dom, 'Milestone Updated');
}

sub extract_inputs ($dom) {
  return $dom->grep(sub($input) {
    $input->attr('name')
      && $input->attr('type') eq 'checkbox' ? $input->attr('checked') : 1;
  })->map(sub ($input) { $input->attr('name'), $input->attr('value') })->to_array;
}

sub delete_milestone ($ua, $url) {
  my $resp    = $ua->get($url)->result;
  my $dom     = $resp->dom;
  my $product = $url->query->param('product');
  check_title($dom, qq{Delete Milestone of Product '$product'});

  my $form   = $dom->at('form[action*="/editmilestones.cgi"]') or die "cannot find form";
  my $action = html_attr_unescape $form->attr('action');
  my %input  = extract_inputs($form->find('input[type="hidden"]'))->@*;
  my $confirm_url = $url->clone;
  $confirm_url->path($action);
  $confirm_url->query(Mojo::Parameters->new);

  my $post_resp = $ua->post($confirm_url, form => \%input)->result;
  my $post_dom = $post_resp->dom;
  check_title($post_dom, 'Milestone Deleted');
}

sub check_title ($dom, $expected_title) {
  my $title = trim($dom->at('title')->text);
  $title =~ s/\s+/ /gs;
  die "Unexpected title: $title, expected $expected_title"
    unless $title eq $expected_title;
}

sub get_milestones ($ua, $urlbase, $product) {
  my $url = $urlbase->clone->path_query('editmilestones.cgi?showbugcounts=1');

  $url->query->merge(product => $product);

  my $resp = $ua->get($url)->result;
  my $dom  = $resp->dom;
  check_title($dom, qq{Select milestone of product '$product'});

  my $header = $dom->find("#admin_table tr[bgcolor='#6666FF'] th")
    ->map(sub($th) { slugify($th->text) })->to_array;

  return $dom->find('#admin_table tr')->map(sub($tr) {
    my $cells = $tr->find('td');
    if ($cells) {
      my %result;
      @result{@$header} = @{$cells->to_array};
      if ($result{bugs}) {
        $result{bugs} = trim($result{bugs}->at('a[href]')->text) + 0;
      }
      if ($result{active}) {
        my $yn = lc(trim($result{active}->text));
        $result{active} = $yn eq 'yes' ? 1 : $yn eq 'no' ? 0 : undef;
      }
      if ($result{sortkey}) {
        $result{sortkey} = trim($result{sortkey}->text);
      }
      if (my $action = delete $result{action}) {
        $result{delete_url} = extract_href($urlbase, $action);
      }
      if (my $edit = delete $result{"edit-milestone"}) {
        $result{edit_url} = extract_href($urlbase, $edit);
        $result{value} = $result{edit_url}->query->param('milestone');
      }
      return undef if all { not defined } values %result;
      return \%result;
    }
    else {
      return undef;
    }
  })->compact->to_array;
}


