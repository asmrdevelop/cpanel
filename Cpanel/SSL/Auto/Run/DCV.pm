package Cpanel::SSL::Auto::Run::DCV;

# cpanel - Cpanel/SSL/Auto/Run/DCV.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::DCV

=head1 SYNOPSIS

    my $dcv_obj = get_user_http_dcv_results( $username, $provider_obj, \@domains );

=head1 DESCRIPTION

This module implements DCV logic for AutoSSL. It determines the DCV
parameters based on the provider’s interface.

=cut

use Try::Tiny;

use Cpanel::Imports;

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Debug                        ();
use Cpanel::Exception                    ();
use Cpanel::Security::Authz              ();
use Cpanel::SSL::DCV                     ();
use Cpanel::SSL::DCV::DNS::Mutex         ();
use Cpanel::SSL::Auto::Run::DCVResult    ();
use Cpanel::Sys::Rlimit                  ();

#overridden in tests
*_verify_http_domains = *Cpanel::SSL::DCV::verify_domains;

# libunbound on its own can’t handle FDs that exceed 1,024. To avoid
# that problem we need to keep the DNS DCV batch size down such that
# we don’t approach that limit. We’ll apply “padding” below to ensure
# that we leave room for Perl to open its own FDs.
use constant _MAX_DNS_DCV_FDS => 1024;

=head1 FUNCTIONS

=head2 $DCV_OBJ = get_user_http_dcv_results( $USERNAME, $PROVIDER_OBJ, \@DOMAINS )

Returns a L<Cpanel::SSL::Auto::Run::DCVResult> instance for the
given username, domains, and provider object (i.e., instance of a
subclass of L<Cpanel::SSL::Auto::Provider>).

This traps errors for individual domains and records the failure into
$DCV_OBJ, but any failure (e.g., failure to drop privileges) that doesn’t
pertain to a specific domain will propagate as an uncaught exception.

=cut

sub get_user_http_dcv_results {
    my ( $username, $provider_obj, $domains_ar ) = @_;

    my @sorted_domains = sort { length($a) <=> length($b) } @$domains_ar;

    my $indent = $provider_obj->create_log_level_indent();

    my $dcv_result_obj = Cpanel::SSL::Auto::Run::DCVResult->new();

    # For now we do all HTTP DCVs, then all DNS DCVs.
    #
    # We minimize overhead by batching all of the DNS updates into
    # a single call.
    #
    # TODO: Implement per-certificate domain limits here so that we
    # don’t do extra DCV operations. (COBRA-7412)

    my @http_failures;

    my $privs = Cpanel::AccessIds::ReducedPrivileges->new($username);

    # NB: This doesn’t throw exceptions (except for sanity-checking
    # logic that shouldn’t bite in production).
    _local_http_dcv_for_multiple_domains(
        \@sorted_domains,
        {
            'provider_obj'     => $provider_obj,
            'dcv_result_obj'   => $dcv_result_obj,
            'http_failures_ar' => \@http_failures,
        }
    );

    return $dcv_result_obj;
}

#----------------------------------------------------------------------

=head2 $batch_size = determine_pre_batch_size( $PROVIDER_OBJ, $USERS_COUNT )

On systems with thousands of users AutoSSL cannot do all DNS DCV checks
at once because each DNS DCV check requires a file descriptor to be held
open, which can cause AutoSSL to exceed its process’s NOFILE rlimit.

Moreover, some libraries that AutoSSL uses may impose their own file
descriptor limits. For example, as of July 2020 L<libunbound(3)> in its
default setup doesn’t work with file descriptors over 1,024.

The solution is to do those DNS DCVs in batches. This returns the size
to use for those batches.

If the size is lower than the given $USERS_COUNT, an C<info>-level log
message is created on $PROVIDER_OBJ to note the batching.

=cut

sub determine_pre_batch_size ( $provider_obj, $users_count ) {

    # Stay beneath the soft NOFILE limit:
    my ($fd_max) = Cpanel::Sys::Rlimit::getrlimit('NOFILE');

    # Honor additional limits that we’ve discovered via trial-and-error:
    if ( $fd_max > _MAX_DNS_DCV_FDS ) {
        $fd_max = _MAX_DNS_DCV_FDS;
    }

    # “Padding” to allow for FDs that AutoSSL may need to open:
    $fd_max -= 200;

    # If the next file descriptor is 20, then we know there are 20 FDs
    # already open, so we narrow our constraint accordingly:
    $fd_max -= _get_next_fd();

    my $batch_size = int( $fd_max / Cpanel::SSL::DCV::DNS::Mutex->FILES_PER_OBJECT );

    die "batch size ($batch_size) is too low!" if $batch_size < 1;

    if ( $batch_size < $users_count ) {
        $provider_obj->log( info => locale()->maketext( '[asis,AutoSSL] will verify [quant,_1,user’s,users’] [asis,TLS] status and [output,acronym,DCV,Domain Control Validation] at a time.', $batch_size ) );
    }

    return $batch_size;
}

sub _get_next_fd {
    local ( $@, $! );

    require Cpanel::TempFH;
    my $tfh = Cpanel::TempFH::create();

    return fileno $tfh;
}

#----------------------------------------------------------------------
# NOTE: This function is no longer used publicly. It is tested directly,
# though.
#
# This logs any HTTP redirections to the PROVIDER_OBJ as C<info>-level
# messages; however, DCV failures themselves are B<not> logged here.
#
# The return is two lists, both of whose orders match $domains_ar:
#   - either a string that describes the DCV failure, or undef on success
#   - a boolean that indicates a no-docroot DCV failure
#
# ^^ TODO: Make the above more robust.

sub _get_local_http_failures_by_domain {
    my ( $provider_obj, $domains_ar ) = @_;

    #Sanity-check/paranoia
    Cpanel::Security::Authz::verify_not_root();

    my $max_redirects = $provider_obj->HTTP_DCV_MAX_REDIRECTS();

    my @provider_dcv_args = (
        dcv_file_allowed_characters     => $provider_obj->URI_DCV_ALLOWED_CHARACTERS(),
        dcv_file_extension              => $provider_obj->EXTENSION(),
        dcv_file_random_character_count => $provider_obj->URI_DCV_RANDOM_CHARACTER_COUNT(),
        dcv_file_relative_path          => $provider_obj->URI_DCV_RELATIVE_PATH(),
        dcv_user_agent_string           => $provider_obj->DCV_USER_AGENT(),
        dcv_max_redirects               => $max_redirects,
    );

    my @report_hrs;

    try {
        @report_hrs = _verify_http_domains(
            domains => $domains_ar,
            @provider_dcv_args,
        );
    }
    catch {
        my $error = $_;

        #We need an error ID to report in the log and to the user.
        if ( !try { $error->isa('Cpanel::Exception') } ) {
            $error = Cpanel::Exception->create_raw("$error");
        }

        #An error here means that something in the DCV logic itself failed.
        #The specifics of that shouldn’t go in the AutoSSL log, so we just
        #put the exception ID into the AutoSSL log and put the full error
        #into the system log.
        Cpanel::Debug::log_warn( "This shouldn't happen! DCV check for @$domains_ar failed due to an uncaught error: " . $error->to_string() );

        my $failure_reason = locale()->maketext( 'An internal error occurred. Check the system log. ([asis,XID:] [_1])', $error->id() );

        @report_hrs = map { { 'failure_reason' => $failure_reason } } @$domains_ar;
    };

    my @http_error_in_order_by_domain;
    my @lacks_docroot_in_order_by_domain;

    for my $domain_id ( 0 .. $#{$domains_ar} ) {
        my $domain    = $domains_ar->[$domain_id];
        my $report_hr = $report_hrs[$domain_id];

        push @lacks_docroot_in_order_by_domain, $report_hr->{'lacks_docroot'};

        if ( $report_hr->{redirects_count} ) {
            _log_redirects( $provider_obj, $domain, $report_hr->{redirects} );
        }

        my $why_bad = $report_hr->{'failure_reason'};

        #Let’s note HTTP redirection overages regardless of
        #whether there’s a failure otherwise.
        if ( $report_hr->{'redirects_count'} && $report_hr->{'redirects_count'} > $max_redirects ) {
            my $note;

            if ($max_redirects) {

                #We don’t state the number of redirections that happened
                #because we number them in _log_redirects().

                $provider_obj->log(
                    'info',
                    locale()->maketext( '[asis,AutoSSL] provider’s redirect limit: [numf,_1]', $max_redirects ),
                );

                $note = locale()->maketext('Excess [asis,DCV] [asis,HTTP] redirection');
            }
            else {
                $note = locale()->maketext( '“[_1]” forbids [asis,DCV] [asis,HTTP] redirections.', $provider_obj->DISPLAY_NAME() );
            }

            if ($why_bad) {
                $provider_obj->log( error => $note );
            }
            else {
                $why_bad = $note;
            }
        }
        push @http_error_in_order_by_domain, $why_bad;
    }
    return \@http_error_in_order_by_domain, \@lacks_docroot_in_order_by_domain;
}

sub _log_redirects {
    my ( $provider_obj, $domain, $redirects ) = @_;

    for my $index ( 0 .. $#$redirects ) {
        my $redirect = $redirects->[$index];

        $provider_obj->log(
            'info',
            locale()->maketext( 'Redirection #[numf,_1] ([_2]): [_3] → [_4]', 1 + $index, $domain, $redirect->url(), $redirect->header('location') ),
        );
    }

    return;
}

sub _local_http_dcv_for_multiple_domains {
    my ( $domains_ar, $state_hr ) = @_;

    my ( $provider_obj, $dcv_result_obj, $http_failures_ar ) = @{$state_hr}{qw(provider_obj dcv_result_obj http_failures_ar)};

    my @domains_to_dcv = @$domains_ar;

    my ( $http_error_in_order_by_domain_ar, $lacks_docroot_in_order_by_domain_ar ) = _get_local_http_failures_by_domain( $provider_obj, \@domains_to_dcv );

    for my $domain (@domains_to_dcv) {
        my $http_error = shift @$http_error_in_order_by_domain_ar;

        my $lacks_docroot_yn = shift @$lacks_docroot_in_order_by_domain_ar;

        if ($http_error) {
            push @$http_failures_ar, $domain;

            # In the specific case of a wildcard domain whose base domain
            # does not exist on the system, we need to give a non-error
            # notification that’s more tailored to how to resolve this.
            #
            if ( $lacks_docroot_yn && ( 0 == rindex( $domain, '*.', 0 ) ) ) {
                my $base = substr( $domain, 2 );

                $provider_obj->log(
                    'warn',
                    locale()->maketext( 'Local [asis,HTTP] [asis,DCV] impediment ([_1]): No base document root exists. To fix this, create a document root for “[_2]”.', $domain, $base ),
                );
            }
            else {
                $provider_obj->log(
                    'warn',
                    locale()->maketext( 'Local [asis,HTTP] [asis,DCV] error ([_1]): [_2]', $domain, $http_error ),
                );
            }
        }
        else {
            $provider_obj->log( 'info', locale()->maketext( 'Local [asis,HTTP] [asis,DCV] OK: [_1]', $domain ) );
        }

        # $dcv is a Cpanel::SSL::Auto::Run::DCVResult
        $dcv_result_obj->add_http( $domain, $http_error );
    }

    return;
}

#----------------------------------------------------------------------

=head2 $DNS_DCV_OBJ = run_dns_dcv( $PROVIDER_OBJ, \@ZONES )

Does DNS DCV for @ZONES, logging to $PROVIDER_OBJ’s log as relevant.

Returns a L<Cpanel::SSL::DCV::DNS::Result> instance.

=cut

sub run_dns_dcv ( $provider_obj, $zones_ar ) {
    $provider_obj->log( info => locale()->maketext( 'Publishing [asis,DNS] changes for local [asis,DNS] [asis,DCV] ([quant,_1,zone,zones]) …', 0 + @$zones_ar ) );

    require Cpanel::SSL::DCV::DNS::Setup;
    my ( $value, $state ) = Cpanel::SSL::DCV::DNS::Setup::set_up_for_zones($zones_ar);

    $provider_obj->log( info => locale()->maketext('Querying [asis,DNS] to confirm [asis,DCV] changes …') );

    require Cpanel::SSL::DCV::DNS;
    return Cpanel::SSL::DCV::DNS::finish_dns_dcv(
        value => $value,
        state => $state,
        zones => $zones_ar,
    );
}

#----------------------------------------------------------------------

=head2 consume_dns_dcv_result( $PROVIDER_OBJ, $AUTOSSL_DCV_OBJ, \@DOMAINS, $DNS_DCV_OBJ )

Updates $AUTOSSL_DCV_OBJ (a L<Cpanel::SSL::Auto::DCVResult> instance)
with the results of $DNS_DCV_OBJ (L<Cpanel::SSL::DCV::DNS::Result>) for
@DOMAINS.

Each result is logged to $PROVIDER_OBJ’s log.

Nothing is returned.

=cut

sub consume_dns_dcv_result {
    my ( $provider_obj, $dcv_obj, $domains_ar, $dns_dcv_obj ) = @_;

    require Cpanel::SSL::DCV::DNS::Constants;
    my $record_name = Cpanel::SSL::DCV::DNS::Constants::TEST_RECORD_NAME();
    my $record_type = Cpanel::SSL::DCV::DNS::Constants::TEST_RECORD_TYPE();

    for my $domain (@$domains_ar) {
        my $why_failed;

        my $dcv_result = $dns_dcv_obj->get_for_domain($domain);

        if ( $dcv_result->{'succeeded'} ) {

            my $msg;

            # If the DCVed domain is the zone name:
            if ( $domain eq $dcv_result->{'zone'} ) {
                $msg = locale()->maketext( 'Local [asis,DNS] [asis,DCV] OK: [_1]', $domain );
            }

            # If the DCVed domain is a subdomain of the zone name:
            else {
                $msg = locale()->maketext( 'Local [asis,DNS] [asis,DCV] OK: [_1] (via [_2])', $domain, $dcv_result->{'zone'} );
            }

            $provider_obj->log( 'info', $msg );
        }
        else {
            if ( $dcv_result->{'failure_reason'} && try { $dcv_result->{'failure_reason'}->isa('Cpanel::LocaleString') } ) {
                $why_failed = $dcv_result->{'failure_reason'}->to_string();
            }
            else {
                $why_failed = locale()->maketext( 'The system’s [asis,DNS] “[_1]” query for “[_2]” failed. The system expected the “[_3]” value.', $record_type, "$record_name.$dcv_result->{'zone'}", $dcv_result->{'dcv_string'} );
            }

            $provider_obj->log( 'error', locale()->maketext( 'Local [asis,DNS] [asis,DCV] error ([_1]): [_2]', $domain, $why_failed ) );
        }

        # This runs on either success or failure.
        # If $why_failed is undef, that tells $dcv_obj
        # that the DCV succeeded.
        $dcv_obj->add_dns( $domain, $why_failed );
    }

    return;
}

1;
