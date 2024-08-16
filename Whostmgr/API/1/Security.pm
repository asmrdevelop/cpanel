package Whostmgr::API::1::Security;

# cpanel - Whostmgr/API/1/Security.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Security - WHM API functions for managing security requirements (like password strengths)

=head1 SYNOPSIS

    use Whostmgr::API::1::Security ();

    my $strengths_hr = Whostmgr::API::1::Security::get_min_pw_strengths();

=head1 DESCRIPTION

This module provides WHM API 1 endpoints to manage password strength requirements and other security related information.

=cut

use Whostmgr::Security      ();
use Whostmgr::API::1::Utils ();

use constant NEEDS_ROLE => {
    set_min_pw_strengths  => undef,
    get_min_pw_strengths  => undef,
    fetch_security_advice => undef,
};

=head1 METHODS

=head2 set_min_pw_strengths($args_hr, $metadata_hr)

Sets the minimum password strength requirements for the system.

=over 3

=item C<< $args_hr >> [in, required]

A hashref containing the name of the password strength setting and the value
for that setting.

See L<Cpanel::PasswdStrength::Constants> for valid names.

If a particular password strength setting is not provided, it is ignored.

If a particular password strength setting is provided but is empty, it is
deleted from the cpanel.config file.

If a particular password strength setting is provided and is valid, it is
set and the cpanel config file is updated.

=item C<< $metadata_hr >> [in, optional]

A hashref of metadata to pass to the api call. Contains the success status
of this call.

=back

B<Returns>: Nothing. See the C<metadata> for the status of the call.

=cut

sub set_min_pw_strengths {
    my ( $args, $metadata ) = @_;

    my ( $ok, $err ) = Whostmgr::Security::set_min_pw_strengths(%$args);

    if ($ok) {
        Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    }
    else {
        @{$metadata}{ 'result', 'reason' } = ( 0, $err );
    }

    return;
}

=head2 get_min_pw_strengths($args_hr, $metadata_hr)

Gets the mininum password strength requirements for the system.

If a password strength setting is missing from the cpanel.config file, the
function will return the default password strength in its place.

=over 3

=item C<< $args_hr >> [in, optional]

A hashref containing the following key(s):

=over 3

=item C<< name >>

A valid password strength setting. See L<Cpanel::PasswdStrength::Constants> for
valid names.

When passed as an argument, this function will only return the corresponding
password strength setting.

If you do not use this parameter, this function returns the minimum password
setting for all values.

=back

=item C<< $metadata_hr >> [in, optional]

A hashref of metadata to pass to the api call. Contains the success status
of this call.

=back

B<Returns>: A hashref consisting of password strength names and their corresponding setting. See the C<metadata> for the status of the call.

=cut

sub get_min_pw_strengths {
    my ( $args, $metadata ) = @_;

    local $@;
    my $strengths_hr = eval { Whostmgr::Security::get_min_pw_strengths( $args->{'name'} ) } or do {
        my $err = $@;
        if ( $err && $err->isa('Cpanel::Exception') ) {
            $err = $err->to_locale_string_no_id();
        }
        @{$metadata}{ 'result', 'reason' } = ( 0, $err );
        return;
    };

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return $strengths_hr;
}

=head2 fetch_security_advice($args_hr, $metadata_hr)

Gets the security advice from the Security Advisor WHM plugin.

=over 3

=item C<< $args_hr >> [in, optional]

A hashref containing data to pass to the api call. Not currently used.

=item C<< $metadata_hr >> [in, optional]

A hashref of metadata to pass to the api call. Contains the success status
of this call.

=back

B<Returns>: A hashref consisting of a C<payload> key with an array of advice
hashes. For example:

    'payload' => [
        {
            key => 'Brute_force_protection_not_enabled',
            suggestion => 'A message about enabling cPHulk goes here with some HTML',
            type => 'ADVISE_WARN',
            summary => 'No brute force protection detected'
        },
        ...
    ]

=cut

sub fetch_security_advice {
    my ( $args, $metadata ) = @_;

    require Cpanel::Security::AdvisorFetch;
    my $msgs = Cpanel::Security::AdvisorFetch::fetch_security_advice();

    for my $msg (@$msgs) {
        next if $msg->{'type'} ne 'mod_advice';

        # white-list the keys that we want to return
        $msg->{'advice'} = { %{ $msg->{'advice'} }{qw( key suggestion text type )} };

        # “text” is a mislabel because we expect HTML for this value.
        # So, send it out as “summary” instead.
        $msg->{'advice'}{'summary'} = delete $msg->{'advice'}{'text'};

        $msg->{'advice'}->{'type'} = Cpanel::Security::Advisor::_lookup_advise_type( $msg->{'advice'}->{'type'} );    # PPI USE OK -- This will never pass the dependency checker since it is not technically in the codebase. However, we always have it installed, so just skip it for now.
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'payload' => $msgs };
}

1;

__END__
