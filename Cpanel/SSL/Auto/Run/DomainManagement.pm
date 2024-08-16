package Cpanel::SSL::Auto::Run::DomainManagement;

# cpanel - Cpanel/SSL/Auto/Run/DomainManagement.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::DomainManagement

=head1 DESCRIPTION

This module implements domain management verification for AutoSSL.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::DNS::Client                ();
use Cpanel::DnsRoots::DomainManagement ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $promises_ar = find_unmanaged_domains( $RESOLVER, $PROVIDER_OBJ, \@DOMAINS );

This module lauches queries for each of @DOMAINS to determine if DNS manages
the domain—i.e., if it has at least one functional authoritative
nameserver.

Each promise resolves to a boolean that indicates whether the domain is
B<unmanaged>.

=cut

sub find_unmanaged_domains ( $resolver, $provider_obj, $domains_ar ) {
    my $domains_count = 0 + @$domains_ar;

    $provider_obj->log( info => locale()->maketext( 'Verifying [quant,_1,domain’s,domains’] management status …', $domains_count ) );

    my @promises;

    my $mgt_promises_ar = Cpanel::DnsRoots::DomainManagement::are_domains_managed(
        $resolver,
        $domains_ar,
    );

    for my $domain (@$domains_ar) {
        my $this_domain = $domain;

        my $promise = shift @$mgt_promises_ar;

        push @promises, $promise->then(
            sub ($is_managed) {
                my ( $level, $msg );

                my @msg_pieces;

                if ($is_managed) {
                    $level = 'info';
                    push @msg_pieces, locale()->maketext( '“[_1]” is managed.', $this_domain );
                }
                else {
                    $level = 'error';

                    push @msg_pieces, locale()->maketext( '“[_1]” is unmanaged.', $this_domain );

                    my (@poss_reg) = Cpanel::DNS::Client::get_possible_registered($domain);

                    if ( @poss_reg == 1 ) {
                        push @msg_pieces, locale()->maketext('Verify this domain’s registration and authoritative nameserver configuration to correct this problem.');
                    }
                    elsif ( @poss_reg == 2 ) {
                        push @msg_pieces, locale()->maketext( 'Verify registration and authoritative nameserver configuration for this domain or “[_1]” to correct this problem.', $poss_reg[1] );
                    }
                    else {
                        push @msg_pieces, locale()->maketext( 'Verify registration and authoritative nameserver configuration for this domain or any of its parent [numerate,_1,domain,domains] to correct this problem.', @poss_reg - 1 );
                    }
                }

                my $indent = $provider_obj->create_log_level_indent();

                $provider_obj->log( $level => "@msg_pieces" );

                return !$is_managed;
            }
        );
    }

    Promise::ES6->all( \@promises )->then(
        sub ($checks_ar) {

            my $good_ct = grep { !$_ } @$checks_ar;

            my $indent = $provider_obj->create_log_level_indent();

            my $bad_ct = $domains_count - $good_ct;

            my @msg;

            if ($bad_ct) {
                if ($good_ct) {
                    push @msg, locale()->maketext( '[asis,AutoSSL] can confirm management status for only [numf,_1] of this user’s [quant,_2,domain,domains].', $good_ct, $domains_count );
                }
                else {
                    push @msg, locale()->maketext( '[asis,AutoSSL] cannot confirm management status for any of this user’s [quant,_1,domain,domains].', $domains_count );
                }

                push @msg, locale()->maketext('[asis,AutoSSL] cannot secure any domain without confirming its management status.');
            }
            else {
                push @msg, locale()->maketext( 'All of this user’s [quant,_1,domain,domains] are managed.', $domains_count );
            }

            $provider_obj->log( info => join( " ", @msg ) );
        }
    );

    return \@promises;
}

1;
