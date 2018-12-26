# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Mojo::Collection::Role::ProgressBar {
  use Mojo::Base -role, -signatures;
  use Term::ProgressBar;

  requires 'each', 'size';

  around each => sub ($each, $self, $cb, $label = undef) {
    my $next_update = 0;
    my $progress = Term::ProgressBar->new(
      {name => $label, count => $self->size, remove => 1, ETA => 'linear'});

    $progress->update(0);
    $self->$each(
      sub ($x, $i) {
        $cb->($x, $i);
        $next_update = $progress->update($i) if $i >= $next_update;
      }
    );
  };
}

1;
