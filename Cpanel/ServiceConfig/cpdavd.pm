package Cpanel::ServiceConfig::cpdavd;

# cpanel - Cpanel/ServiceConfig/cpdavd.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::ServiceConfig::cpdavd

=head1 DESCRIPTION

This module extends L<Cpanel::ServiceConfig::cPanel> for cpdavd.
It also implements a bit of non-OO logic; see below.

=cut

#----------------------------------------------------------------------

our $VERSION = '1.2';

use parent 'Cpanel::ServiceConfig::cPanel';

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class. (Wraps the base class’s method of the same name.)

=cut

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    require Cpanel::Locale;
    $self->{'display_name'}   = Cpanel::Locale::lh()->maketext('[asis,cPanel] Web Disk');
    $self->{'type'}           = 'cpdavd';
    $self->{'datastore_name'} = 'cpdavd';

    return $self;
}

=head1 STATIC FUNCTIONS

These are to be called I<NOT> as object nor class methods, but as
plain functions, e.g.:

    Cpanel::Service::Config::cpdavd::die_if_unneeded();

=head2 die_if_unneeded()

Convenience function that throws C<unneeded_phrase()> if cpdavd is unneeded.
Returns nothing otherwise.

The thrown exception includes a stack trace because it always
indicates a bug in the software.

=cut

sub die_if_unneeded {
    if ( !is_needed() ) {
        require Carp;
        Carp::confess( unneeded_phrase() );
    }

    return;
}

=head2 $yn = is_needed()

Returns a boolean that indicates whether cpdavd is needed given
the active cPanel & WHM profile and installed plugins.

=cut

sub is_needed () {
    require Cpanel::DAV::Ports;

    return !!%{ Cpanel::DAV::Ports::get_ports() };
}

=head2 $str = unneeded_phrase()

Returns a human-readable phrase that indicates that cpdavd is unneeded.

=cut

sub unneeded_phrase () {
    require Cpanel::Locale;
    return Cpanel::Locale::lh()->maketext('No enabled server role requires [asis,cpdavd].');
}

1;
