package Cpanel::Security::Authn::APITokens::Validate;

# cpanel - Cpanel/Security/Authn/APITokens/Validate.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::APITokens::Validate

=head1 SYNOPSIS

See subclasses.

=head1 DESCRIPTION

This module provides validation of the parts of an API token
that pertain to any service and that need to be generally
accessible.

=cut

#----------------------------------------------------------------------

use Cpanel::Validate::Time ();
use Cpanel::Exception      ();
use Cpanel::Set            ();

# NB: This is the set of characters for the URL variant of base 64.
use constant _NAME_ALLOWED_CHARS => ( 'a-z', 'A-Z', '0-9', '_', '-' );

use constant MAX_LENGTH => 50;

#----------------------------------------------------------------------

=head1 CLASS METHODS

=head2 I<CLASS>->NON_NAME_TOKEN_PARTS()

Returns a list of the parts of a token that aren’t names.

=cut

sub NON_NAME_TOKEN_PARTS {
    return ( 'expires_at', 'whitelist_ips', $_[0]->_NON_NAME_TOKEN_PARTS() );
}

#----------------------------------------------------------------------

=head2 I<CLASS>->validate_creation( \%PARAMS )

Validates API token creation. %PARAMS are the pieces of the API token
to specify on creation: C<name> as well as the service-specific
parameters.

Errors are thrown on unrecognized
parameters, invalid C<name>, or failed service-specific validation.

Nothing is returned.

=cut

sub validate_creation ( $class, $opts_hr ) {
    $class->_validate_common( $opts_hr, { required_parts => ['name'] } );
    return;
}

=head2 I<CLASS>->validate_update( \%PARAMS )

Validates an API token update. %PARAMS are as for C<create()> but
may also include C<new_name> to indicate a rename.

Errors are thrown on unrecognized
parameters, invalid C<new_name>, missing update operation,
or failed service-specific validation.

Nothing is returned.

=cut

sub validate_update ( $class, $opts_hr ) {
    $class->_validate_common(
        $opts_hr,
        {
            required_parts => ['name'],
            optional_parts => ['new_name']
        }
    );

    # If only the required name part exists then there is nothing to update.
    if ( keys %{$opts_hr} == 1 && $opts_hr->{name} ) {
        die $class->_err_no_update();
    }

    return;
}

sub _validate_expires_at ($time) {
    return 1 if !length $time;

    Cpanel::Validate::Time::epoch_or_die($time);

    if ( $time != 0 && $time < time() ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” value must be a future date.", [$time] );
    }
    return 1;

}

sub _validate_ip_or_range ($ip_or_range) {
    return 1 if !length $ip_or_range;

    require Cpanel::Validate::IP;
    require Net::IP;

    # Net::IP is more restrictive in some ways than Cpanel::Validate::IP, and
    # since it is being used to determine if an IP is allowed or disallowed, it
    # is important that Net::IP returns an object.
    if ( Cpanel::Validate::IP::is_valid_ip_cidr_or_prefix($ip_or_range) && eval { Net::IP->new($ip_or_range) } ) {
        return 1;
    }

    die Cpanel::Exception::create( 'InvalidParameter', "Invalid [numerate,_1,IP address or CIDR range,IP addresses or CIDR ranges] specified: [list_and,_2]", [ 1, $ip_or_range ] );
}

sub _validate_token_name ($name) {
    my $max_length = MAX_LENGTH;

    if ( !length($name) || $name !~ m/^[A-Za-z0-9_-]{1,$max_length}$/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,API] token name. An [asis,API] token name must not be longer than [quant,_2,character,characters] and may only contain the following [numerate,_3,character,characters]: [join, ,_4]', [ $name, $max_length, 64, [ _NAME_ALLOWED_CHARS() ] ] );
    }

    return;
}

sub _validate_whitelist_ips ($whitelist_ar) {
    if ( defined $whitelist_ar ) {
        my $size = scalar @{$whitelist_ar};
        if ( $size > 100 ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'You have entered “[_1]” [asis,IP] addresses, which is above the limit of 100.', [$size] );
        }
        foreach my $whitelist_ip (@$whitelist_ar) {
            _validate_ip_or_range($whitelist_ip);
        }
    }
    return;
}

sub _validate_common ( $class, $opts_hr, $validate_opts = {} ) {

    if ( my @missing = grep { !length $opts_hr->{$_} } @{ $validate_opts->{'required_parts'} // [] } ) {
        die Cpanel::Exception::create( 'MissingParameters', [ 'names' => \@missing ] );
    }

    if (
        my @extras = Cpanel::Set::difference(
            [ keys %{$opts_hr} ],
            [
                @{ $validate_opts->{'required_parts'} // [] },
                @{ $validate_opts->{'optional_parts'} // [] },
                $class->NON_NAME_TOKEN_PARTS()
            ],
        )
    ) {
        die Cpanel::Exception::create_raw( 'InvalidParameters', 'Unrecognized API token update parameter(s): ' . join( ' ', @extras ) );
    }

    my %part_validator = (
        expires_at    => \&_validate_expires_at,
        name          => \&_validate_token_name,
        new_name      => \&_validate_token_name,
        whitelist_ips => \&_validate_whitelist_ips,
    );
    foreach my $part ( sort keys %part_validator ) {
        if ( defined $opts_hr->{$part} ) {
            $part_validator{$part}->( $opts_hr->{$part} );
        }
    }

    $class->_validate_service_parts($opts_hr);

    return;
}
1;
