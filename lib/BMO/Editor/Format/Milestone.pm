# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package BMO::Editor::Format::Milestone {
  use Mojo::Base -base, -signatures;
  use Role::Tiny::With;

  use BMO::Editor::Item;
  use Set::Object qw(set);

  with 'BMO::Editor::Format';

  has checkbox_value => sub { {'_' => 0, 'x' => 1} };

  sub _encode ($self, $id, $content) {
    my $line = sprintf('id:%.4x %5d %-25s %s (%5d bugs)',
      $id, $content->{sortkey}, $content->{value},
                       $content->{active} ? '[x]' : '[_]',
                       $content->{bugs} // 0);
    return $line;
  }

  sub _decode ($self, $line) {
    if ($line =~ /^id:([[:xdigit:]]{4})\s+(\d+)\s+(.+?)\s+\[([_x])\]/) {
      my ($id, $sortkey, $value, $checkbox) = @{^CAPTURE};
      my $active = $self->checkbox_value->{$checkbox};
      die "Bad checkbox: $checkbox" unless defined $active;

      return BMO::Editor::Item->new(
        id      => hex($id),
        content => {sortkey => $sortkey, active => $active, value => $value},
      );
    }
    elsif ($line =~ /^\((\d+)\)\s+(.+?)\s+\[([_x])\]/) {
      my ($sortkey, $checkbox, $value) = @{^CAPTURE};
      my $active = $self->checkbox_value->{$checkbox};
      die "Bad checkbox: $checkbox" unless defined $active;

      return BMO::Editor::Item->new(
        content => {sortkey => $sortkey, active => $active, value => $value},
      );
    }
    elsif (not $line =~ /^#/){
      die "Bad line: $line\n";
    }
  }
}

1;

