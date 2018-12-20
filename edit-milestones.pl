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
      $_->{bugs}, $_->{milestone},)
  } @milestones;
  my @edited = Proc::InvokeEditor->edit(\@unedited, '.txt');

  my $unedited_ids = set(map {/^([[:xdigit:]]{4})/} @unedited);
  my $edited_ids   = set(map {/^([[:xdigit:]]{4})/} @edited);

  my @to_delete = map { hex($_) } ($unedited_ids - $edited_ids)->members;

  say "Going to remove:\n\t",
    join("\n\t", map { $_->{milestone} } @milestones[@to_delete]);
}

sub extract_href ($urlbase, $dom) {
  my $link = $dom->at('a[href]');
  if ($link) {
    my $url = Mojo::URL->new(html_attr_unescape $link->attr('href'));
    $url->host('bugzilla.mozilla.org');
    $url->scheme('https');
  }
  else {
    return undef;
  }
}

sub delete_milestone ($ua, $url) {
  my $resp    = $ua->get($url)->result;
  my $dom     = $resp->dom;
  my $product = $url->query->param('product');
  check_title($dom, qq{Delete Milestone of Product '$product'});

  my $form = $dom->at('form[action*="/editmilestones.cgi"]') or die "cannot find form";
  my $action = html_attr_unescape $form->attr('action');
  my %form_data = $form->find('input[type="hidden"]')
    ->map(sub ($input) { $input->attr('name'), $input->attr('value') })->to_array->@*;
  $url->path($action);
  $url->query(Mojo::Parameters->new);

  my $post_resp = $ua->post($url, form => \%form_data)->result;
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
        $result{milestone} = $result{edit_url}->query->param('milestone');
      }
      return undef if all { not defined } values %result;
      return \%result;
    }
    else {
      return undef;
    }
  })->compact->to_array;
}


