# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package BMO::Editor::Format;
use Mojo::Base -role, -signatures;
use Mojo::Util qw(sha1_sum);
use Set::Object;
use BMO::Editor::Item;

requires '_encode', '_decode';

has ids       => sub { Set::Object->new };
has checksums => sub { {} };

sub encode ($self, $content) {
  my $id = $self->ids->size;
  my $line = $self->_encode($id, $content);
  $self->checksums->{$id} = sha1_sum($line);
  $self->ids->insert($id);
  return $line;
}

sub decode ($self, $line) {
  my $item = $self->_decode($line) or return undef;
  my $id   = $item->id;
  if (defined $id) {
    die "Unknown id: $id" unless $self->ids->contains($id);
    $item->is_modified($self->checksums->{$id} ne sha1_sum($line));
  }
  else {
    $item->is_new(1);
  }
  return $item;
}
1;
