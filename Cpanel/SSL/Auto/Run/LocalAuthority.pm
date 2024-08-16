package Cpanel::SSL::Auto::Run::LocalAuthority;

# cpanel - Cpanel/SSL/Auto/Run/LocalAuthority.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::LocalAuthority

=head1 DESCRIPTION

This module implements local-authority checks for AutoSSL. This happens
prior to DNS DCV as a pre-validation; any domains for which the local
server lacks authority in DNS will not get DNS DCV (and will thus be
considered unsecureable).

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::DnsUtils::Authority::Async ();
use Cpanel::Exception                  ();
use Cpanel::PromiseUtils               ();
use Cpanel::Set                        ();

my $authty_obj;

END { undef $authty_obj }

#----------------------------------------------------------------------

=head1 METHODS

=head2 filter_dns_dcv_domains_by_local_authority( \@DOMAINS, $DCV_OBJ, $PROVIDER_OBJ )

This function runs a local-authority check for each of @DOMAINS.
Any domains for which the local server lacks authority will be removed
from @DOMAINS, with an explanation added to $DCV_OBJ (an instance of
L<Cpanel::SSL::Auto::Run::DCVResult>).

$PROVIDER_OBJ is an instance of L<Cpanel::SSL::Auto::Provider> but
is used just for logging.

=cut

sub filter_dns_dcv_domains_by_local_authority ( $domains_ar, $dcv_obj, $provider_obj ) {    ## no critic qw(ManyArgs) - mis-parse
    $provider_obj->log( info => locale()->maketext( 'Verifying local authority for [quant,_1,domain,domains] …', 0 + @$domains_ar ) );
    my $indent = $provider_obj->create_log_level_indent();

    $authty_obj ||= Cpanel::DnsUtils::Authority::Async->new();

    my $p_ar = $authty_obj->has_local_authority($domains_ar);

    my @promises_processed;

    my @dns_dcv_ok;

    for my $i ( 0 .. $#$domains_ar ) {
        my $domain  = $domains_ar->[$i];
        my $promise = $p_ar->[$i];

        push @promises_processed, $promise->then(
            sub ($result_hr) {
                if ( $result_hr->{'local_authority'} ) {
                    $provider_obj->log( info => locale()->maketext( 'Local authority confirmed: “[_1][comment,domain name]”', $domain ) );
                    push @dns_dcv_ok, $domain;
                }
                else {
                    my ( $loglevel, $dcv_msg );

                    if ( my $err = $result_hr->{'error'} ) {
                        $err = Cpanel::Exception::get_string($err);

                        $loglevel = 'error';
                        $dcv_msg  = locale()->maketext( 'Failed to determine local authority for “[_1][comment,domain name]”: [_2][comment,error]', $domain, $err );
                    }
                    else {
                        $loglevel = 'info';
                        $dcv_msg  = locale()->maketext( 'No local authority: “[_1][comment,domain name]”', $domain );
                    }

                    $provider_obj->log( $loglevel => $dcv_msg );

                    $dcv_obj->add_dns( $domain, $dcv_msg );
                }
            },
        );
    }

    Cpanel::PromiseUtils::wait_anyevent(@promises_processed);

    @$domains_ar = Cpanel::Set::intersection(
        $domains_ar,
        \@dns_dcv_ok,
    );

    return;
}

1;
