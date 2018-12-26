# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package BMO::Editor::Format::JSON;
use Mojo::Base -base, -signatures;
use Role::Tiny::With;

use BMO::Editor::Item;
use Mojo::JSON qw(encode_json decode_json);

with 'BMO::Editor::Format';

has checkbox_value => sub { {'_' => 0, 'x' => 1} };

sub _encode ($self, $id, $content) {
  return encode_json([$id, $content]);
}

sub _decode ($self, $line) {
  my ($id, $content) = decode_json($line)->@*;
  return BMO::Editor::Item->new(id => $id, content => $content);
}

sub header { }

1;

