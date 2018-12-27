# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package BMO::Tool;
use Mojo::Base -base, -signatures;
use Mojo::Collection qw(c);
use Mojo::Cookie::Response;
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json);
use Mojo::UserAgent;
use Mojo::Util qw(slugify trim html_attr_unescape);
use POSIX qw(ceil);
use Set::Object qw(set);
use curry;

has urlbase => sub {
  my $urlbase = $ENV{BMO_URLBASE} // 'https://bugzilla.allizom.org';
  return Mojo::URL->new($urlbase);
};

has config => sub($self) {
  my $config_file = path($ENV{BMO_TOOL_CONFIG} // "config.json");
  return decode_json($config_file->slurp);
};

has ua => sub($self) {
  my $ua      = Mojo::UserAgent->new();
  my $cookies = $self->config->{cookies}{$self->urlbase->host};
  $ua->cookie_jar->ignore(sub {0});
  $ua->cookie_jar->add(
    map {
      Mojo::Cookie::Response->new(
        name     => $_,
        value    => $cookies->{$_},
        domain   => $self->urlbase->host,
        secure   => $self->urlbase->scheme eq 'https' ? 1 : undef,
        httponly => 1,
        path     => '/',
        )
    } keys %$cookies
  );
  $ua->max_redirects(2);
  $ua->transactor->name('BMO::Tool (owner: dylan@mozilla.com)');
  return $ua;
};

has _milestones => sub { +{} };
has _versions   => sub { +{} };

sub url ($self, $path) { $self->urlbase->clone->path_query($path) }

sub browse ($self, $cb) {
  local $_ = $self->ua;
  my $resp = $cb->($self->ua)->result;
  my $dom  = $resp->dom->with_roles('BMO::Helper::DOM');
  return $dom;
}

sub click_link ($self, $dom, $text) {
  my $link = $dom->find_links('a[href*="/buglist.cgi"]', $text)->first;
  return $link ? $self->browse(sub { $_->get($self->url($link)) }) : undef;
}

sub post_form ($self, $form, $cb) {
  die "No form!"   unless defined $form;
  die "Not a form" unless $form->tag eq 'form';
  my $action   = html_attr_unescape $form->attr('action');
  my $post_url = $self->url($action);
  my $fields   = $form->extract_inputs;
  local $_ = $fields;
  $cb->($fields);
  $self->browse(sub { $_->post($post_url, form => $fields) });
}

sub has_milestone ($self, $product, $milestone) {
  my $set = $self->_milestones->{$product} or return 0;
  return $set->contains($milestone);
}

sub _milestones_url ($self, $product, $action = 'list', $milestone = undef) {
  my %query = (product => $product);
  if ($action eq 'list') {
    $query{showbugcounts} = 1;
  }
  else {
    $query{action} = $action;
  }
  if (defined $milestone) {
    $query{milestone} = $milestone;
  }
  return $self->url('editmilestones.cgi')->query(%query);
}

sub add_milestone ($self, $product, $milestone, $sortkey) {
  return if $self->has_milestone($product, $milestone);

  my $url   = $self->_milestones_url($product, 'add');
  my $title = qq{Add Milestone to Product '$product'};
  my $dom   = $self->browse(sub { $_->get($url) })->check_title($title);
  my $form  = $dom->at('form[action="/editmilestones.cgi"]');
  my $dom2  = $self->post_form(
    $form,
    sub {
      $_->{milestone} = $milestone;
      $_->{sortkey}   = $sortkey;
    }
  )->check_title('Milestone Created');
  $self->_milestones->{$product} //= set();
  $self->_milestones->{$product}->insert($milestone);
  return $dom2;
}

sub delete_milestone ($self, $product, $milestone) {
  return unless $self->has_milestone($product, $milestone);

  my $url   = $self->_milestones_url($product, 'del', $milestone);
  my $title = qq{Delete Milestone of Product '$product'};
  my $dom   = $self->browse(sub { $_->get($url) })->check_title($title)
    ->check_error_table();
  my $form = $dom->at('form[action="/editmilestones.cgi"]');
  my $dom2 = $self->post_form($form, sub { })->check_title('Milestone Deleted');
  $self->_milestones->{$product} //= set();
  $self->_milestones->{$product}->remove($milestone);
}

sub edit_milestone ($self, $product, $milestone, $cb) {
  my $url   = $self->_milestones_url($product, 'edit', $milestone);
  my $title = qq{Edit Milestone '$milestone' of product '$product'};
  my $dom   = $self->browse(sub { $_->get($url) })->check_title($title);
  my $form  = $dom->at('form[action="/editmilestones.cgi"]');
  return $self->post_form($form, $cb)->check_title('Milestone Updated');
}

sub get_milestones ($self, $product) {
  my $url        = $self->_milestones_url($product);
  my $title      = qq{Select milestone of product '$product'};
  my $dom        = $self->browse(sub { $_->get($url) })->check_title($title);
  my $milestones = $dom->extract_admin_table->map(sub($row) {
    my %result;
    if (my $bugs = $row->{bugs}) {
      $result{bugs} = 0 + trim($bugs->at('a[href]')->text);
    }
    if (my $active = $row->{active}) {
      my $yn = lc(trim($active->text));
      $result{active} = $yn eq 'yes' ? 1 : $yn eq 'no' ? 0 : undef;
    }
    if (my $sortkey = $row->{sortkey}) {
      $result{sortkey} = 0 + trim($sortkey->text);
    }
    if (my $action = $row->{action}) {
      $result{can_delete} = trim($action->all_text) eq 'Delete' ? 1 : 0;
    }
    if (my $edit = $row->{"edit-milestone"}) {
      my $edit_url = $edit->extract_href($self->urlbase);
      $result{value} = html_attr_unescape $edit_url->query->param('milestone');
    }
    return (keys %result) ? \%result : undef;
  })->compact;

  my $set = set($milestones->map(sub { $_->{value} })->to_array->@*);
  $self->_milestones->{$product} = $set;

  return $milestones;
}

sub move_milestones ($self, $product, $milestone, $name) {
  my $limit = 10;
  my $url   = $self->url('buglist.cgi')
    ->query(product => $product, target_milestone => $milestone->{value});
  my $f = sub($input) {
    $input->{target_milestone} = $name;
  };
  my $loop = c(1 .. ceil($milestone->{bugs} / $limit));
  $self->add_milestone($product, $name, $milestone->{sortkey});
  $loop->with_roles('+ProgressBar')
    ->each(sub { $self->edit_bugs($url, $limit, $f)->at('main') },
    "Fix milestone on $milestone->{bugs} bugs");
  $self->delete_milestone($product, $milestone->{value});
}

sub has_version ($self, $product, $version) {
  my $set = $self->_versions->{$product} or return 0;
  return $set->contains($version);
}

sub _versions_url ($self, $product, $action = 'list', $version = undef) {
  my %query = (product => $product);
  if ($action eq 'list') {
    $query{showbugcounts} = 1;
  }
  else {
    $query{action} = $action;
  }
  if (defined $version) {
    $query{version} = $version;
  }
  return $self->url('editversions.cgi')->query(%query);
}

sub add_version ($self, $product, $version) {
  return if $self->has_version($product, $version);

  my $url   = $self->_versions_url($product, 'add');
  my $title = qq{Add Version to Product '$product'};
  my $dom   = $self->browse(sub { $_->get($url) })->check_title($title);
  my $form  = $dom->at('form[action="/editversions.cgi"]');
  my $dom2  = $self->post_form($form, sub { $_->{version} = $version })
    ->check_title('Version Created');
  $self->_versions->{$product} //= set();
  $self->_versions->{$product}->insert($version);
  return $dom2;
}

sub delete_version ($self, $product, $version) {
  return unless $self->has_version($product, $version);

  my $url   = $self->_versions_url($product, 'del', $version);
  my $title = qq{Delete Version of Product '$product'};
  my $dom   = $self->browse(sub { $_->get($url) })->check_title($title);
  my $form = $dom->at('form[action="/editversions.cgi"]');
  my $dom2 = $self->post_form($form, sub { })->check_title('Version Deleted');
  $self->_versions->{$product} //= set();
  $self->_versions->{$product}->remove($version);
}

sub edit_version ($self, $product, $version, $cb) {
  my $url   = $self->_versions_url($product, 'edit', $version);
  my $title = qq{Edit Version '$version' of product '$product'};
  my $dom   = $self->browse(sub { $_->get($url) })->check_title($title);
  my $form  = $dom->at('form[action="/editversions.cgi"]');
  return $self->post_form($form, $cb)->check_title('Version Updated');
}

sub move_versions ($self, $product, $version, $name) {
  my $limit = 10;
  my $url   = $self->url('buglist.cgi')
    ->query(product => $product, version => $version->{value});
  my $f = sub($input) {
    $input->{version} = $name;
  };
  my $loop = c(1 .. ceil($version->{bugs} / $limit));
  $self->add_version($product, $name);
  $loop->with_roles('+ProgressBar')
    ->each(sub { $self->edit_bugs($url, $limit, $f) },
    "Fix version on $version->{bugs} bugs");
  $self->delete_version($product, $version->{value});
}

sub get_versions ($self, $product) {
  my $url      = $self->_versions_url($product, 'list');
  my $title    = qq{Select version of product '$product'};
  my $dom      = $self->browse(sub { $_->get($url) })->check_title($title);
  my $versions = $dom->extract_admin_table->map(sub($row) {
    my %result;
    if (my $bugs = $row->{bugs}) {
      $result{bugs} = 0 + trim($bugs->at('a[href]')->text);
    }
    if (my $active = $row->{active}) {
      my $yn = lc(trim($active->text));
      $result{active} = $yn eq 'yes' ? 1 : $yn eq 'no' ? 0 : undef;
    }
    if (my $action = $row->{action}) {
      $result{can_delete} = trim($action->all_text) eq 'Delete' ? 1 : 0;
    }
    if (my $edit = $row->{"edit-version"}) {
      my $edit_url = $edit->extract_href($self->urlbase);
      $result{value} = html_attr_unescape $edit_url->query->param('version');
    }
    return (keys %result) ? \%result : undef;
  })->compact;

  my $set = set($versions->map(sub { $_->{value} })->to_array->@*);
  $self->_versions->{$product} = $set;

  return $versions;
}

sub edit_bugs ($self, $url, $limit, $cb) {
  my $dom = $self->browse(sub { $_->get(_tweak_url($url, $limit)) })
    ->check_title('Bug List');
  my $form = $dom->check_title('Bug List')->at('form[action="/process_bug.cgi"]');
  my $ids
    = $form->find('input[type="checkbox"][name^="id_"]')->map('attr', 'name');
  my $post_dom = $self->post_form(
    $form,
    sub ($input) {
      $ids->each(sub { $input->{$_} = 1 });
      $cb->($input);
    }
  );
  return $post_dom->check_throw_error();
}

sub _tweak_url ($url, $n) {
  $url->clone->tap(sub { $_->query->merge(limit => $n, tweak => 1) });
}

1;
