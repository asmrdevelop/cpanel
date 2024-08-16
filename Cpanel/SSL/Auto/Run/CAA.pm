package Cpanel::SSL::Auto::Run::CAA;

# cpanel - Cpanel/SSL/Auto/Run/CAA.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::CAA

=head1 DESCRIPTION

This module holds AutoSSL’s logic for handling CAA records.

=cut

#----------------------------------------------------------------------

use Promise::ES6 ();

use Cpanel::Imports;

use Cpanel::DnsRoots::CAA ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 apply_needed_caa_records( $PROVIDER_OBJ, \@DOMAINS )

This function examines @DOMAINS and applies whatever CAA records are
needed to allow the CA to issue SSL for @DOMAINS.

($PROVIDER_OBJ is an instance of L<Cpanel::SSL::Auto::Provider>.)

This logic currently has a number of problems. For example, it doesn’t
distinguish between C<issue> and C<issuewild> tags, and it assumes that
all CAA records exist on the zone’s base domain. (B<FIXME>)

Nothing is returned.

=cut

sub apply_needed_caa_records ( $provider_obj, $domains_ar ) {
    require Cpanel::SSL::CAA;

    my %uniq;
    @uniq{ map { s<\A\*\.><>r } @$domains_ar } = ();

    $provider_obj->log( info => locale()->maketext('Attempting to ensure the existence of necessary [asis,CAA] records …') );

    my $indent = $provider_obj->create_log_level_indent();

    my @altered = Cpanel::SSL::CAA::ensure_ca_authorization(
        [ $provider_obj->CAA_STRING(), $provider_obj->EXTRA_CAA_STRINGS() ],
        sort( sort { length $a <=> length $b } keys %uniq ),
    );

    if (@altered) {
        for my $name_tag_ar (@altered) {
            my ( $dnsname, $tag ) = @$name_tag_ar;
            $provider_obj->log( info => locale()->maketext( '[asis,CAA] “[_1]” record created: “[_2]”', $tag, $dnsname ) );
        }

        _wait_for_dns_changes_to_apply($provider_obj);
    }
    else {
        $provider_obj->log( info => locale()->maketext( 'No [asis,CAA] records were created.', ) );
    }

    return;
}

=head2 promise(\@bad) = find_forbidden_domains( $PROVIDER_OBJ, \@DOMAINS )

This function queries public DNS to determine which of @DOMAINS the
given provider’s CA is forbidden to secure via SSL.

($PROVIDER_OBJ is an instance of L<Cpanel::SSL::Auto::Provider>.)

This function will also log (via $PROVIDER_OBJ) about forbiddances.

NO The return is a promise that resolves to a reference to an array of
NO forbidden domains.

The return is a reference to an array of promises, one for each @DOMAINS.
Each promise resolves to a boolean: truthy if CAA forbids the domain,
falsy if CAA allows. Each promise treats errors as nonfatal, resolving
to undef on failure.

=cut

sub find_forbidden_domains ( $resolver, $provider_obj, $domains_ar ) {
    my $domains_count = 0 + @$domains_ar;

    $provider_obj->log( info => locale()->maketext( 'Verifying “[_1]”’s authorization on [quant,_2,domain,domains] via [asis,DNS] [asis,CAA] records …', $provider_obj->DISPLAY_NAME(), $domains_count ) );

    my @caa_strings = (
        $provider_obj->CAA_STRING(),
        $provider_obj->EXTRA_CAA_STRINGS(),
    );

    my $promises_ar = Cpanel::DnsRoots::CAA::get_forbiddance_promises(
        $resolver,
        \@caa_strings,
        $domains_ar,
    );

    my @all_processed;

    for my $domain (@$domains_ar) {
        my $promise = shift @$promises_ar;

        push @all_processed, $promise->then(
            sub ($prohibition_ar) {
                my ( $level, $msg );

                if ($prohibition_ar) {
                    $level = 'error';

                    # push @caa_forbidden_domains, $domain;

                    my ( $rrset_owner, $owner_cname ) = @$prohibition_ar;

                    if ($owner_cname) {
                        if ( $rrset_owner eq $domain ) {
                            $msg = locale()->maketext( '[asis,CA] forbidden: “[_1]” (alias of “[_2]”)', $domain, $owner_cname );
                        }
                        else {
                            $msg = locale()->maketext( '[asis,CA] forbidden: “[_1]” (via “[_2]”, alias of “[_3]”)', $domain, $rrset_owner, $owner_cname );
                        }
                    }
                    elsif ( $rrset_owner eq $domain ) {
                        $msg = locale()->maketext( '[asis,CA] forbidden: “[_1]”', $domain );
                    }
                    else {
                        $msg = locale()->maketext( '[asis,CA] forbidden: “[_1]” (via “[_2]”)', $domain, $rrset_owner );
                    }
                }
                else {
                    $level = 'info';
                    $msg   = locale()->maketext( '[asis,CA] authorized: “[_1]”', $domain );
                }

                my $indent = $provider_obj->create_log_level_indent();

                $provider_obj->log( $level => $msg );

                return !!$prohibition_ar;
            },
        );
    }

    Promise::ES6->all( \@all_processed )->then(
        sub ($prohibited_ar) {

            my @authorized = grep { !$_ } @$prohibited_ar;

            my $indent = $provider_obj->create_log_level_indent();

            if (@authorized) {
                $provider_obj->log( info => locale()->maketext( '“[_1]” is authorized to issue certificates for [numf,_2] of this user’s [quant,_3,domain,domains].', $provider_obj->DISPLAY_NAME(), 0 + @authorized, 0 + @$prohibited_ar ) );
            }
            else {
                $provider_obj->log( info => locale()->maketext( '[asis,DNS] [asis,CAA] records forbid “[_1]” from issuing certificates for any of this user’s [quant,_2,domain,domains].', $provider_obj->DISPLAY_NAME(), 0 + @$prohibited_ar ) );
            }
        }
    );

    return \@all_processed;
}

#----------------------------------------------------------------------

our $_DNS_APPLY_TIME;

# Sleep for as long as expect to wait for the dns server
# to reload the zonefile
sub _wait_for_dns_changes_to_apply ($provider_obj) {
    require Cpanel::Config::LoadCpConf;

    $_DNS_APPLY_TIME //= ( Cpanel::Config::LoadCpConf::loadcpconf_not_copy()->{'bind_deferred_restart_time'} + 4.5 );

    # We need to wait for the DNS changes to be
    # reloaded so the CAA record update takes
    # effect before we do DCV
    $provider_obj->log( info => locale()->maketext( 'Waiting [quant,_1,second,seconds] for the [asis,DNS] changes to take effect …', $_DNS_APPLY_TIME ) );

    _sleep($_DNS_APPLY_TIME);

    return;
}

# mocked in tests
sub _sleep ($secs) {
    return sleep $secs;
}

1;
