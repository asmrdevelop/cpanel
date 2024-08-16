package Cpanel::Install::Job;

# cpanel - Cpanel/Install/Job.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Install::Job

=head1 DESCRIPTION

Base class for a component of a cPanel & WHM installation.

This is a “first stab” at an envisioned framework for modularizing
cPanel & WHM’s installation.

=head1 HOW TO WRITE AN INSTALL JOB MODULE

All job modules must subclass this class.

Subclasses must implement the following methods:

=over

=item * C<_DESCRIPTION> - Must be a L<Cpanel::LocaleString> instance,
or an instance of some other class that implements C<to_string()>.

=item * C<_run()> - Implements the module’s work.

=back

The following are optional:

=over

=item * C<_NEEDS> - defaults to empty

=item * C<_IS_CRITICAL()> - boolean, defaults to 0

=back

The following internal methods are available to subclasses:

=over

=item * C<_logger()> - Exposes the C<logger> object that the constructor
receives.

=back

=cut

#----------------------------------------------------------------------

use Cpanel::Install::JobRunner::Constants ();

use Class::XSAccessor {
    getters => {
        _logger => 'logger',
    },
};

use constant _NEEDS => ();

use constant _IS_CRITICAL => 0;

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->new( %OPTS )

Constructor. %OPTS are:

=over

=item * C<logger> - A L<Cpanel::Install::JobRunner::Logger> instance.

=back

=cut

sub new ( $class, %opts ) {
    my %self = (
        logger => $opts{'logger'} || die('need “logger”'),
    );

    return bless \%self, $class;
}

#----------------------------------------------------------------------

=head2 $yn = I<OBJ>->is_critical()

Whether the object’s job is considered “critical”; i.e.,
cPanel & WHM installation is a failure if I<OBJ>’s work fails.

May be called as a class method.

=cut

sub is_critical ($self) {
    return $self->_IS_CRITICAL();
}

#----------------------------------------------------------------------

=head2 $yn = I<OBJ>->get_short_name()

Returns the class name with the common namespace trimmed.

May be called as a class method.

=cut

sub get_short_name ($self_or_class) {
    my $PKG = Cpanel::Install::JobRunner::Constants::JOBS_NAMESPACE();

    my $class = ( ref $self_or_class ) || $self_or_class;

    return ( $class =~ s<\A\Q$PKG\E::><>r );
}

#----------------------------------------------------------------------

=head2 @needs = I<OBJ>->get_needs()

Returns the modules whose work must be completed before this one’s.

May be called as a class method.

=cut

sub get_needs ($self) {
    return $self->_NEEDS();
}

#----------------------------------------------------------------------

=head2 $string = I<OBJ>->get_description()

Returns the module’s human-readable description.

May be called as a class method.

=cut

sub get_description ($self) {
    return $self->_DESCRIPTION()->to_string();
}

#----------------------------------------------------------------------

=head2 $string = I<OBJ>->run()

Does the module’s work.

=cut

sub run ($self) {

    # Having the child class implement a separate _run() method rather than
    # the public run() method accomplishes (at least) these boons:
    #
    # 1) An easy way now exists for the base class to implement logic
    # before and/or after the child class’s work (should need for such arise).
    #
    # 2) The public interface is defined and documented in exactly one place.
    #
    return $self->_run();
}

1;
