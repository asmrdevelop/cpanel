package Cpanel::PublicContact;

# cpanel - Cpanel/PublicContact.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::PublicContact - reader for the PublicContact datastore

=head1 SYNOPSIS

    my $contact_hr = Cpanel::PublicContact->get('reseller_name');

    #Only for when performance is a must:
    my $json_sr = Cpanel::PublicContact->get_json_sr('reseller_name');

=head1 DESCRIPTION

PublicContact is a datastore for resellers to expose contact information for
domains that are hosted on “their” servers. Since “BobsHosting” doesn’t want
people to contact Hostgator about a site that’s run by one of BobsHosting’s
users, we have PublicContact as a means for resellers to list themselves as
the point of contact (after WHOIS) for the domain.

=cut

use constant PARTS => (
    'url',
    'name',
);

use Cpanel::LoadFile                     ();
use Cpanel::LoadModule                   ();
use Cpanel::Validate::FilesystemNodeName ();

our $BASEDIR = '/var/cpanel/public_contact';

=head1 METHODS

=head2 $contact_hr = I<CLASS>->get( RESELLER_USERNAME )

Returns the given reseller’s public contact information
as a hash reference. Each public contact item (e.g., C<name>, C<url>)
is present, at least as an empty string.

=cut

sub get {
    my ( $class, $username ) = @_;
    my $data_hr;

    while ($username) {
        my $json_sr = $class->get_json_sr($username);

        if ($$json_sr) {
            Cpanel::LoadModule::load_perl_module('Cpanel::JSON');
            $data_hr = Cpanel::JSON::Load($$json_sr);
        }

        $data_hr->{$_} //= q<> for $class->PARTS();

        # Can't find good data for this reseller? Try again as root.
        # Note we don't support multi-level resellers here, so no love for zamfoo
        $username = ( $username ne 'root' && !grep { $data_hr->{$_} } $class->PARTS() ) ? 'root' : undef;
    }

    return $data_hr;
}

=head2 $ref = I<CLASS>->get_json_sr( RESELLER_USERNAME )

Returns the public contact data as a scalar reference to a JSON string.
If there is no contact data for the given user, the reference is to undef.

=cut

sub get_json_sr {
    my ( $class, $username ) = @_;

    return \Cpanel::LoadFile::load_if_exists( $class->_get_user_path($username) );
}

=head2 sanitize_details

Sanitize Public Contact Information for display

=over 2

=item Input

=over 3

=item C<HASHREF>

$public_contact_hr - a hash reference containing a name and a url

=item C<SCALAR>

$host - this is the hostname to be used in creating webmaster@ urls

=back

=item Output

=over 3

=item C<HASHREF>

returns a hash ref containing name and url keys

=back

=back

=cut

sub sanitize_details {
    my ( $public_contact_hr, $host ) = @_;

    if ( !$public_contact_hr ) {
        die "missing public contact hashref!";
    }

    if ( !$host ) {
        die "missing host!";
    }

    $public_contact_hr->{'name'} = $public_contact_hr->{'url'} if !$public_contact_hr->{'name'};
    $public_contact_hr->{'name'} = 'webmaster@' . $host        if !$public_contact_hr->{'name'};

    if ( !$public_contact_hr->{'url'} || $public_contact_hr->{'url'} =~ m/^javascript:/i ) {
        $public_contact_hr->{'url'} = 'webmaster@' . $host;
    }
    if ( index( $public_contact_hr->{'url'}, 'mailto:' ) != 0 && index( $public_contact_hr->{'url'}, '@' ) > 0 ) {
        $public_contact_hr->{'url'} = 'mailto:' . $public_contact_hr->{'url'};
    }
    elsif ( index( $public_contact_hr->{'url'}, 'mailto:' ) != 0 && index( $public_contact_hr->{'url'}, "http" ) != 0 ) {
        $public_contact_hr->{'url'} = 'http://' . $public_contact_hr->{'url'};
    }

    return;
}

#----------------------------------------------------------------------

sub _BASEDIR { return $BASEDIR }

sub _get_user_path {
    my ( $class, $username ) = @_;

    #sanity
    Cpanel::Validate::FilesystemNodeName::validate_or_die($username);

    return "$BASEDIR/$username";
}
