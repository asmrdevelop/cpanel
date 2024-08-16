package Whostmgr::MinimumAccounts;

# cpanel - Whostmgr/MinimumAccounts.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::MinimumAccounts

=head1 SYNOPSIS

    my $min_accts = Whostmgr::MinimumAccounts->new();

    my $at_least_2_accts_exist = $min_accts->server_has_at_least(2);

=head1 DESCRIPTION

This stores an optimized implementation of a minimum-accounts checker.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie ('exists');
use Cpanel::ConfigFiles                            ();
use Cpanel::Config::LoadUserDomains::Count::Active ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    return bless {}, $class;
}

=head1 $yn = I<OBJ>->server_has_at_least( $MINIMUM )

Returns a boolean that indicates whether the server has at least $MINIMUM
cPanel users.

=cut

sub server_has_at_least ( $self, $min ) {
    return $self->{$min} //= do {
        if ( $min == 1 ) {
            my $exists = Cpanel::Autodie::exists($Cpanel::ConfigFiles::TRUEUSERDOMAINS_FILE);
            ( $exists && ( -s _ ) > 2 ) ? 1 : 0;
        }
        elsif ( $min == 2 ) {
            my $exists = Cpanel::Autodie::exists($Cpanel::ConfigFiles::TRUEUSERDOMAINS_FILE);

            if ( $exists && ( -s _ ) > 512 ) {    # They have at least 2 so lets avoid opening the file
                1;
            }
            else {
                $self->_get_users_count() >= $min ? 1 : 0;
            }
        }
        else {
            $self->_get_users_count() >= $min ? 1 : 0;
        }
    };
}

sub _get_users_count ($self) {
    return $self->{'__users_count'} //= Cpanel::Config::LoadUserDomains::Count::Active::count_active_trueuserdomains();
}

1;
