package Cpanel::Admin::Modules::Cpanel::apitokens;

# cpanel - Cpanel/Admin/Modules/Cpanel/apitokens.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Security::Authn::APITokens::Write::cpanel ();

use constant _actions => (
    'CREATE',
    'UPDATE',
    'REVOKE',
);

sub _init {
    my ($self) = @_;

    $self->cpuser_has_feature_or_die('apitokens');

    return;
}

sub _whitelist_EntryAlreadyExists {
    my ($self) = @_;

    $self->whitelist_exception(
        'Cpanel::Exception::EntryAlreadyExists',
    );

    return;
}

sub CREATE {
    my ( $self, %args ) = @_;

    die 'Partial-access tokens are disabled!' if $args{'features'} && @{ $args{'features'} };

    $self->_whitelist_EntryAlreadyExists();

    return $self->_do_token_obj_action( create_token => \%args );
}

sub UPDATE {
    my ( $self, %args ) = @_;

    if ( $args{'features'} || $args{'has_full_access'} ) {
        die 'Invalid arguments!';
    }

    $self->_whitelist_EntryAlreadyExists();

    return $self->_do_token_obj_action( update_token => \%args );
}

sub REVOKE {
    my ( $self, $name ) = @_;

    return $self->_do_token_obj_action( revoke_token => $name );
}

sub _do_token_obj_action {
    my ( $self, $action, @args ) = @_;

    my $tokens_obj = Cpanel::Security::Authn::APITokens::Write::cpanel->new( { user => $self->get_caller_username() } );

    my $result = $tokens_obj->$action(@args);
    $tokens_obj->save_changes_to_disk();

    return $result;
}

1;
