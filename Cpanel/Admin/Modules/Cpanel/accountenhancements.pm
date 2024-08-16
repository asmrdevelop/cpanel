package Cpanel::Admin::Modules::Cpanel::accountenhancements;

# cpanel - Cpanel/Admin/Modules/Cpanel/accountenhancements.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Exception;
use Whostmgr::AccountEnhancements;

use constant _demo_actions => ('LIST');

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::accountenhancements

=head1 SYNOPSIS

use Cpanel::AdminBin::Call ();
Cpanel::AdminBin::Call::call( "Cpanel", "accountenhancements", "LIST" );

=head1 DESCRIPTION

This admin bin is for listing Account Enhancements as the adminbin user. These
operations require privileges that are not available to the regular users.

=cut

sub _actions {
    my ($self) = @_;

    return (
        $self->SUPER::_actions,
        'LIST',
    );
}

sub _get_cpuser_data() {
    my ($self) = @_;

    return Cpanel::Config::LoadCpUserFile::load_or_die( $self->get_caller_username() );
}

sub _get_REMOTE_USER() {
    my ($self) = @_;

    return $self->_get_cpuser_data()->{'OWNER'} || 'root';
}

=head1 FUNCTIONS

=head2 LIST

Lists the Account Enhancements assigned to an account.

=head3 RETURNS

=over 4

=item list - a list of Account Enhancements.

=item list - a list of warnings, if any were encountered.

=back

=cut

sub LIST {
    my ($self) = @_;
    my $user = $self->get_caller_username();

    local $ENV{'REMOTE_USER'} = $self->_get_REMOTE_USER();
    my ( $ae_ref, $warnings_ref ) = eval { Whostmgr::AccountEnhancements::findByAccount($user); };
    die Cpanel::Exception::create( 'AdminError', [ message => $@->to_string_no_id() ] ) if $@;

    return ( $ae_ref, $warnings_ref );
}

1;
