package Cpanel::License::CompanyID;

# cpanel - Cpanel/License/CompanyID.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::License::CompanyID - Obtain the CompanyID provided by the License

=head1 SYNOPSIS

    use Cpanel::License::CompanyID;

    Cpanel::License::CompanyID::get_company_id();

=head1 DESCRIPTION

Obtain the CompanyID provided by the License

=cut

use constant ENOENT => 2;

our $CPANEL_DIRECT_COMPANY_ID = '265';
our $Cached_ID;

sub _companyid_file { return '/var/cpanel/companyid'; }

sub _read_company_id {
    my $id = readlink( _companyid_file() . '.fast' );
    return $id if defined $id;

    if ( $! != ENOENT() ) {
        die sprintf( "readlink(%s): %s", _companyid_file() . '.fast', "$!" );
    }

    local $@;
    eval 'require Cpanel::LoadFile' or die;    ##no critic qw(StringyEval)

    $id = Cpanel::LoadFile::load_if_exists( _companyid_file() );

    if ( defined $id ) {
        if ( $id !~ tr<0-9><>c ) {
            return $id;
        }

        warn sprintf( "Invalid company ID in %s: “%s”", _companyid_file(), $id );
    }

    return;
}

=head2 get_company_id

Get the cPanel License CompanyID

=over 2

=item Output

=over 3

=item C<SCALAR>

    company id as provided by the cPanel license

=back

=back

=cut

sub get_company_id {

    if ($Cached_ID) {
        return $Cached_ID;
    }

    return $Cached_ID = _read_company_id();

}

=head2 is_cpanel_direct

Returns a boolean indicating that the current license was issued by cPanel Store

=over 2

=item Output

=over 3

=item C<SCALAR>

    a boolean indicating that the current license was issued by cPanel Store

=back

=back

=cut

sub is_cpanel_direct {

    return get_company_id() && get_company_id() eq $Cpanel::License::CompanyID::CPANEL_DIRECT_COMPANY_ID;

}

1;
