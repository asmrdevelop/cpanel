package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/Base.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base

=head1 DESCRIPTION

This is a base class for preflight analysis modules for remote-root
configuration transfers. Subclasses of this class describe how to
perform analysis on different configuration transfer modules.

You’ll need to coordinate subclasses of this module with
subclasses of L<Whostmgr::Config::Backup::Base>.

=cut

#----------------------------------------------------------------------

use Cpanel::Locale ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

Instantiates I<CLASS>. Subclasses may define what %OPTS can be.

=cut

sub new ( $class, %OPTS ) {
    return bless \%OPTS, $class;
}

sub cpconftool_module ($self) {
    return $self->_BACKUP_NAMESPACE();
}

#----------------------------------------------------------------------

=head2 $commands_ar = I<OBJ>->get_analysis_commands()

Returns a reference to an array of commands to execute to analyze
the transfer module support on a server.

TODO: Document the output format of this function.

=cut

sub get_analysis_commands ($self) {
    return [
        # Phase 0
        [],

        # Phase 1 is anything that needs to happen AFTER we modify something phase 0
        # usually nothing goes here unless we have to do something in a specific order

        []
    ];
}

=head2 I<OBJ>->parse_analysis_commands( $REMOTE_DATA_HR )

TODO: Document what exactly this should accept and return.
(See subclasses of this module for examples.)

=cut

sub parse_analysis_commands ( $self, $REMOTE_DATA_HR ) {
    return $self->_parse_analysis_commands($REMOTE_DATA_HR);
}

#----------------------------------------------------------------------

=head1 REQUIRED SUBCLASS METHODS

=head2 I<CLASS>->_parse_analysis_commands( $REMOTE_DATA_HR )

Implementation of C<parse_analysis_commands()> as described above.

=head2 I<CLASS>->_BACKUP_NAMESPACE()

The namespace under which the module’s configuration data resides
in the backup.

This should normally match what the corresponding backup
module creates; e.g., for
L<Whostmgr::Config::Backup::Easy::Apache> it would be
C<cpanel::easy::apache>. (It can’t be fully automated because
of that C<easy> part.)

=cut

#----------------------------------------------------------------------

=head1 OPTIONAL SUBCLASS METHODS

=head2 I<CLASS>->name()

A name for the module that the UI will display. Defaults to the
last level of the package name.

=cut

sub name ($self_or_class) {
    my $pkg = ref($self_or_class) || $self_or_class;

    return $pkg =~ s<.+::><>r;
}

=head2 I<CLASS>->_ANALYSIS_KEY_SUFFIX()

Thus far either C<INFO> (default) or C<VERSION>.

=cut

use constant _ANALYSIS_KEY_SUFFIX => 'INFO';

#----------------------------------------------------------------------

sub _analysis_key ($self) {

    return $self->_module_name() . '_' . $self->_ANALYSIS_KEY_SUFFIX();
}

=head2 get_analysis_key

Get the Analysis Key for the current module

=over 2

=item Output

=over 3

=item C<SCALAR>

string value representing the analysis module

=back

=back

=cut

sub get_analysis_key ($self) {
    return $self->_analysis_key();
}

*_module_name = *name;

sub _locale ($self) {

    return ( $self->{'_locale'} ||= Cpanel::Locale->get_handle() );
}

1;
