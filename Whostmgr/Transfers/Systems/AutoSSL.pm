package Whostmgr::Transfers::Systems::AutoSSL;

# cpanel - Whostmgr/Transfers/Systems/AutoSSL.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::AutoSSL

=head1 SYNOPSIS

N/A

=head1 DESCRIPTION

This module exists to be called from the account restore system.
It should not be invoked directly except from that framework.

It restores the user’s custom AutoSSL configuration parameters
from the account archive. Its restricted and unrestricted modes
are identical.

=head1 METHODS

=cut

use strict;
use warnings;

use Try::Tiny;

use parent qw(
  Whostmgr::Transfers::Systems
);

use Cpanel::Autodie                 ();
use Cpanel::LoadFile                ();
use Cpanel::JSON                    ();
use Cpanel::SSL::Auto::Exclude::Set ();

use constant {
    get_prereq               => ['Domains'],
    get_restricted_available => 1,
};

=head2 I<OBJ>->get_summary()

POD for cplint. Don’t call this directly.

=cut

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores [asis,AutoSSL] settings.') ];
}

=head2 I<OBJ>->restricted_restore()

POD for cplint. Don’t call this directly.

=cut

sub restricted_restore {
    my ($self) = @_;

    my $extractdir = $self->extractdir();

    if ( Cpanel::Autodie::exists("$extractdir/autossl.json") ) {
        my $json     = Cpanel::LoadFile::load("$extractdir/autossl.json");
        my $assl_cfg = Cpanel::JSON::Load($json);

        my %domains_lookup;
        @domains_lookup{ @{ $assl_cfg->{'excluded_domains'} } } = ();

        my $max_loops  = scalar keys %domains_lookup;
        my $loop_count = 0;
        while ( %domains_lookup && $loop_count <= $max_loops ) {
            try {
                Cpanel::SSL::Auto::Exclude::Set::set_user_excluded_domains(
                    user    => $self->newuser(),
                    domains => [ keys %domains_lookup ],
                );

                #We’re done!
                %domains_lookup = ();
            }
            catch {
                if ( try { $_->isa('Cpanel::Exception::DomainOwnership') } ) {
                    my $domains_ar = $_->get('domains');

                    for my $domain (@$domains_ar) {
                        $self->warn( $self->_locale()->maketext( 'This account archive does not contain a domain named “[_1]”. The system will not add this domain to the restored account’s [asis,AutoSSL] exclusions.', $domain ) );
                        delete $domains_lookup{$domain};
                    }
                }
                else {
                    # Something else that we cannot handle
                    local $@ = $_;
                    die;
                }
            };

            $loop_count++;
        }
    }

    return 1;
}

*unrestricted_restore = *restricted_restore;

1;
