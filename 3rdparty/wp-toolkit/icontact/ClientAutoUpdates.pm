package Cpanel::iContact::Class::WPT::ClientAutoUpdates;

use strict;

use parent qw(
  Cpanel::iContact::Class
);

# Any Variables that are both required and that you want
# the template to include should go here.
my @required_args = qw(failure_updates_text failure_updates_list available_updates_text available_updates_list installed_updates_text installed_updates_list requirements_updates_text requirements_updates_list);

my @optional_args = qw();

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @required_args,
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        map { $_ => $self->{'_opts'}{$_} } ( @required_args, @optional_args )
    );
}

1;
