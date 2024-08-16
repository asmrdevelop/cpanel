package Cpanel::API::ContactInformation;

# cpanel - Cpanel/API/ContactInformation.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::API::ContactInformation

=head1 DESCRIPTION

This module will supersede legacy methods of altering contact information
from cPanel & Webmail.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel                     ();
use Cpanel::AdminBin::Call     ();
use Cpanel::APICommon::Error   ();
use Cpanel::CustInfo::Model    ();    ## PPI NO PARSE - uses constant
use Cpanel::Validate::EmailRFC ();
use Cpanel::Try                ();

use constant _EMAIL_FIELDS => qw( email  second_email );

my $_needs_contact_features = {
    needs_feature => {
        match    => 'any',
        features => [ 'updatecontact', 'updatenotificationprefs' ],
    },
};

our %API = (
    set_email_addresses   => $_needs_contact_features,
    unset_email_addresses => $_needs_contact_features,
);

#----------------------------------------------------------------------

=head1 API FUNCTIONS

=head2 set_email_addresses()

See L<https://go.cpanel.net/contactinformation-set_contact_addresses>.

=cut

sub set_email_addresses ( $args, $result ) {
    return if !_authorize_for_cpuser_only($result);

    my @addrs = $args->get_length_required_multiple('address');

    if ( @addrs > Cpanel::CustInfo::Model::EMAIL_FIELDS ) {
        $result->raw_error( locale()->maketext( 'Give no more than [quant,_1,email address,email addresses].', 0 + Cpanel::CustInfo::Model::EMAIL_FIELDS ) );
        return 0;
    }
    else {
        for my $addr (@addrs) {
            Cpanel::Validate::EmailRFC::is_valid_remote_or_die($addr);
        }
    }

    return _save_addresses( $args, $result, \@addrs );
}

sub _save_addresses ( $args, $result, $addrs_ar ) {
    my $admin_ok;
    my $api_method = $ENV{'TEAM_USER'} ? 'SET_TEAM_CONTACT_EMAIL_ADDRESSES' : 'SET_CONTACT_EMAIL_ADDRESSES';

    Cpanel::Try::try(
        sub {
            Cpanel::AdminBin::Call::call(
                'Cpanel', 'cpuser', $api_method,
                $args->get_length_required('password'),
                [ $args->get_multiple('old_address') ],
                $addrs_ar,
            );

            $admin_ok = 1;
        },

        'Cpanel::Exception::Stale' => sub ($err) {
            my $old_addrs = $err->get('addresses');

            $result->error('old_address list is incorrect');

            $result->data(
                Cpanel::APICommon::Error::convert_to_payload(
                    'Stale',
                    old_addresses => $old_addrs,
                ),
            );
        },

        'Cpanel::Exception::WrongAuthentication' => sub {
            $result->raw_error( locale()->maketext('Incorrect password given.') );
        },

        'Cpanel::Exception::RateLimited' => sub {
            $result->raw_error( locale()->maketext('Try again later.') );
        },
    );

    return $admin_ok;
}

sub unset_email_addresses ( $args, $result ) {
    return if !_authorize_for_cpuser_only($result);

    return _save_addresses( $args, $result, [] );
}

sub _authorize_for_cpuser_only ($result) {
    return 1 if $ENV{'TEAM_USER'};                    # team users are authorized.
    return 1 if $Cpanel::user eq $Cpanel::authuser;

    # No need to give a “pretty” error?
    $result->error('cpuser only; webmail users forbidden');

    return 0;
}

# TODO: Remove as part of COBRA-13746, since we won’t need to
# update the contactinfo files anymore.
sub _custinfo_impl_args {
    return (
        appname   => $Cpanel::appname,
        cpuser    => $Cpanel::user,
        cphomedir => $Cpanel::homedir,
        username  => $Cpanel::user,
    );
}

1;
