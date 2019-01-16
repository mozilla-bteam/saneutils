# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package BMO::Helper::DOM;
use Mojo::Base -role, -signatures;

use Mojo::Util qw(trim html_attr_unescape slugify);
use Mojo::Collection qw(c);
use Carp;

requires 'at', 'find';

sub check_title ($dom, $expected_title) {
  my $title = trim($dom->at('title')->text) =~ s/\s+/ /rsg;
  die "Unexpected title: $title, expected $expected_title\n"
    unless $title eq $expected_title;
  return $dom;
}

sub check_error_table ($dom) {
  my $error = $dom->at('table[bgcolor="red"] tr td');
  if ($error) {
    my $msg = $error->all_text;
    die $msg =~ s/\s+/ /grs;
  }
  return $dom;
}

sub check_throw_error ($dom) {
  my $error = $dom->at('#error_msg.throw_error');
  if ($error) {
    my $msg = $error->all_text;
    die $msg =~ s/\s+/ /grs;
  }
  return $dom;
}

sub extract_href ($dom, $urlbase) {
  my $link = $dom->at('a[href]');
  if ($link) {
    my $url = Mojo::URL->new(html_attr_unescape $link->attr('href'));
    $url->host($urlbase->host);
    $url->scheme($urlbase->scheme);
  }
  else {
    return undef;
  }
}

sub extract_inputs ($dom) {
  my $extract = sub { [$_->attr('name') || $_->attr('id'), $_->attr('value')] };
  my $unpair = sub {
    map { html_attr_unescape $_ } @$_;
  };
  my $hidden  = $dom->find('input[type="hidden"]')->map($extract);
  my $checked = $dom->find('input[type="checkbox"][checked]')->map($extract);
  my $text   = $dom->find('input[type="text"], input:not([type])')->map($extract);
  my $select = $dom->find('select[name]')->map(sub {
    my $option = $_->at('option[selected]') || $_->at('option');
    $option ? [$_->attr('name'), $option->attr('value')] : undef;
  });
  my $inputs = c($hidden, $checked, $text, $select);
  my %inputs = $inputs->map(sub {
    $_->compact->grep(sub { defined $_->[1] })->map($unpair)->@*;
  })->@*;
  return \%inputs;
}

sub extract_admin_table($dom) {
  my $sel    = '#admin_table tr[bgcolor="#6666FF"] th';
  my @header = $dom->find($sel)->map('text')->map(\&slugify)->@*;

  return $dom->find('#admin_table tr:not([bgcolor])')->map(sub($tr) {
    if (my $cells = $tr->find('td')) {
      my %result;
      @result{@header} = $cells->to_array->@*;
      return \%result;
    }
    else {
      return undef;
    }
  })->compact;
}

sub find_links ($dom, $selector, $text) {
  my $slug = slugify($text);
  $dom->find($selector)->grep(sub { slugify($_->all_text) eq $slug })->map(sub {
    return Mojo::URL->new(html_attr_unescape $_->attr('href'));
  });
}

1;
