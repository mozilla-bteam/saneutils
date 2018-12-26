# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package BMO::Editor {
  use Mojo::Base -base, -signatures;

  use Mojo::Collection qw(c);
  use Mojo::Loader qw(load_class);
  use Proc::InvokeEditor;
  use Set::Object qw(set);
  use curry;

  has invoke_editor => sub { \&_default_invoke_editor };

  sub edit ($self, $name, $c) {
    my $format      = $self->new_format($name);
    my $lines       = $c->map($format->curry::encode);
    my $items       = $self->invoke_editor->($lines)->map($format->curry::decode);
    my $removed_ids = $format->ids - set($items->map('id')->@*);
    my $removed     = c($removed_ids->@*)->map(sub {
      BMO::Editor::Item->new(id => $_, content => $c->[$_], is_removed => 1);
    });

    return ($items, $removed);
  }

  sub _default_invoke_editor($lines) {
    $lines->new(Proc::InvokeEditor->edit($lines->to_array));
  }

  sub new_format ($self, $name) {
    my $class = "BMO::Editor::Format::$name";
    load_class($class);
    return $class->new;
  }
}

1;
