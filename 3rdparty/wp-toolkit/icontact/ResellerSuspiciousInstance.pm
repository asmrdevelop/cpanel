package Cpanel::iContact::Class::WPT::ResellerSuspiciousInstance;

use strict;

use parent qw(
  Cpanel::iContact::Class
);

# Any Variables that are both required and that you want
# the template to include should go here.
my @required_args = qw(suspicious_instance_text suspicious_instance_details_info);

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
