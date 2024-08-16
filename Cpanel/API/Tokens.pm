package Cpanel::API::Tokens;

# cpanel - Cpanel/API/Tokens.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::API::Tokens

=head1 SYNOPSIS

Called the same way as any other UAPI module.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception ();

our %API;

BEGIN {
    my %all_access = ( needs_role => undef );

    %API = (
        _needs_feature => 'apitokens',

        #create_limited     => \%all_access,
        create_full_access => \%all_access,
        rename             => \%all_access,

        #set_features       => \%all_access,
        #set_full_access    => \%all_access,
        revoke => \%all_access,
        list   => \%all_access,
    );
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 create_limited()

Accepts C<name> and a list of C<feature>s.

Returns C<create_time> and C<token>.

=cut

#sub create_limited {
#    my ( $args, $result ) = @_;
#
#    return _create(
#        $args, $result,
#        features => [ $args->get_length_required_multiple('feature') ],
#    );
#}

sub _create {
    my ( $args, $result, %admin_args ) = @_;

    $admin_args{'name'} = $args->get_length_required('name');
    my $expires_at = $args->get('expires_at');
    if ( defined $expires_at ) {
        $admin_args{'expires_at'} = $expires_at;
    }

    require Cpanel::Security::Authn::APITokens::Validate::cpanel;
    Cpanel::Security::Authn::APITokens::Validate::cpanel->validate_creation( $Cpanel::user, \%admin_args );

    require Cpanel::AdminBin::Call;
    my $resp_hr = Cpanel::AdminBin::Call::call(
        'Cpanel', 'apitokens', 'CREATE',
        %admin_args,
    );

    delete @{$resp_hr}{ 'name', 'features', 'has_full_access', 'expires_at' };

    $result->data($resp_hr);

    return 1;
}

=head2 create_full_access()

Accepts C<name>, C<expires_at>.

Returns C<create_time> and C<token>.

=cut

sub create_full_access {
    my ( $args, $result ) = @_;

    return _create(
        $args, $result,
        has_full_access => 1,
    );
}

#----------------------------------------------------------------------

=head2 rename( %ARGS ) {

Accepts C<name> and C<new_name>.

Fails if the two are the same.

Returns nothing.

=cut

sub rename {
    my ( $args, $result ) = @_;

    _update(
        $args,
        new_name => $args->get_length_required('new_name'),
    );

    return 1;
}

=head2 set_features( %ARGS ) {

Accepts C<name> and a list of C<feature>s.
If the token has full access, this call will revoke that status.

Returns 1 if the token’s features changed, or 0 if the given list
already matched the current one.

=cut

#sub set_features {
#    my ( $args, $result ) = @_;
#
#    my $changed_yn = _update(
#        $args,
#        has_full_access => 0,
#        features        => [ $args->get_length_required_multiple('feature') ],
#    );
#
#    $result->data($changed_yn);
#
#    return 1;
#}

#=head2 set_full_access( %ARGS ) {
#
#Accepts C<name>.
#
#Returns 1 if the token’s features changed, or 0 if the token
#was already a full-access token.
#
#=cut
#
#sub set_full_access {
#    my ( $args, $result ) = @_;
#
#    $result->data( _update( $args, has_full_access => 1 ) );
#
#    return 1;
#}

sub _update {
    my ( $args, %admin_args ) = @_;

    $admin_args{'name'} = $args->get_length_required('name');

    # Reject renames that aren’t renames. (This is probably a courtesy
    # to the caller, who has no reason to send off such a request.)
    if ( defined $admin_args{'new_name'} ) {
        if ( $admin_args{'new_name'} eq $admin_args{'name'} ) {
            die Cpanel::Exception->create( '“[_1]” must be a different value from “[_2]”.', [ 'new_name', 'name' ] );
        }
    }

    require Cpanel::Security::Authn::APITokens::cpanel;
    my $tokens_obj = Cpanel::Security::Authn::APITokens::cpanel->new( { user => $Cpanel::user } );
    my $existing   = $tokens_obj->get_token_details_by_name( $admin_args{'name'} );

    if ( !$existing ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The [asis,API] token “[_1]” does not exist.', [ $admin_args{'name'} ] );
    }

    #    if ( !defined $admin_args{'new_name'} ) {
    #
    #        # Forgo a non-rename admin call if we’re already where we want.
    #        # (We already rejected the similar case for renames above.)
    #        # We indicate this state with a 0 return from the API.
    #        if ( $admin_args{'has_full_access'} ) {
    #            if ( $existing->has_full_access() ) {
    #                return 0;
    #            }
    #        }
    #        else {
    #            my @old = sort @{ $existing->export()->{'features'} };
    #            my @new = sort @{ $admin_args{'features'} };
    #
    #            if ( @old == @new ) {
    #                if ( !grep { $old[$_] ne $new[$_] } 0 .. $#old ) {
    #                    return 0;
    #                }
    #            }
    #        }
    #    }

    require Cpanel::Security::Authn::APITokens::Validate::cpanel;
    Cpanel::Security::Authn::APITokens::Validate::cpanel->validate_update( $Cpanel::user, $existing, \%admin_args );

    require Cpanel::AdminBin::Call;
    Cpanel::AdminBin::Call::call(
        'Cpanel', 'apitokens', 'UPDATE', %admin_args,
    );

    return 1;
}

#----------------------------------------------------------------------

=head2 list()

This implements the same interface as
L<Cpanel::Security::Authn::APITokens::cpanel>’s C<read_tokens()> method.
The return is a list of hashes from that class’s C<export()> method.

=cut

sub list {
    my ( $args, $result ) = @_;

    require Cpanel::Security::Authn::APITokens::cpanel;
    my $tokens_obj = Cpanel::Security::Authn::APITokens::cpanel->new( { user => $Cpanel::user } );

    my $tokens_hr = $tokens_obj->read_tokens();

    $result->data( [ values %$tokens_hr ] );

    return 1;
}

#----------------------------------------------------------------------

=head2 revoke( $NAME )

This accepts C<name> and returns either:

=over

=item * 1: A token with the given C<name> was removed.

=item * 0: No token with the given C<name> existed anyway.

=back

=cut

sub revoke {
    my ( $args, $result ) = @_;

    my $name = $args->get_length_required('name');

    return _return_admin( $result, 'REVOKE', $name );
}

#----------------------------------------------------------------------

sub _return_admin {
    my ( $result, @args ) = @_;

    require Cpanel::AdminBin::Call;
    my $resp = Cpanel::AdminBin::Call::call( 'Cpanel', 'apitokens', @args );

    $result->data($resp);

    return 1;
}

1;
