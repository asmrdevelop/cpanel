package Cpanel::SSLDelete;

# cpanel - Cpanel/SSLDelete.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::userdata::Load       ();
use Cpanel::Domain::TLS                  ();
use Cpanel::Domain::TLS::Write           ();
use Cpanel::HttpUtils::ApRestart::BgSafe ();
use Cpanel::Locale                       ();
use Cpanel::Logger                       ();
use Cpanel::ServerTasks                  ();
use Cpanel::SSLInstall::Propagate        ();
use Crypt::Format                        ();

=encoding UTF-8

=head1 NAME

Cpanel::SSLDelete

=head1 SYNOPSIS

    use Cpanel::SSLDelete ();
    my ( $worked, $data_or_msg ) = Cpanel::SSLDelete::realdelsslhost(
        'some.host.name',
        'cpuser',
    );
    die "whoops: $data_or_msg" if !$worked;
    ... # Do something with $data_or_msg hash if you want

=head1 DESCRIPTION

Module for deleting an SSL Vhost. Used to exist in duplicate over in:
* bin/whostmgr2.pl's realdelsslhost
* bin/admin/Cpanel/ssl.pl's DEL action

=head1 SUBROUTINES

=head2 realdelsslhost( STRING $host, STRING $domainowner )

Returns ARRAY( $success, $info_hr OR $message_string )
$success: Whether the call encountered GreatSuccess™
$info_hr: Any information about the process we may have wanted to
convey to the user including the deleted vhost data.
$message: Additional information about failures.

=cut

sub realdelsslhost {
    my ( $host, $domainowner ) = @_;

    require Cpanel::Config::WebVhosts;
    my $wvh = Cpanel::Config::WebVhosts->load($domainowner);

    my $servername = $wvh->get_vhost_name_for_domain($host) or do {
        return ( 0, { 'message' => "Failed to identify web vhost for “$host”!" } );
    };

    my $vh_ud = Cpanel::Config::userdata::Load::load_ssl_domain_userdata( $domainowner, $servername );
    if ( !$vh_ud || !%$vh_ud ) {
        my $locale = Cpanel::Locale->get_handle();

        if ( $servername eq $host ) {
            return ( 0, { 'message' => $locale->maketext( 'No [asis,SSL] certificate secures the website “[_1]”.', $host ) } );
        }

        return ( 0, { 'message' => $locale->maketext( 'No [asis,SSL] certificate secures “[_1]”’s website ([_2]).', $host, $servername ) } );
    }

    require Cpanel::Apache::TLS;
    my $cert_bin = do {
        my ($cert_pem) = Cpanel::Apache::TLS->get_certificates($servername);
        Crypt::Format::pem2der($cert_pem);
    };

    # Presume failure to begin with
    local $@;
    my $transaction = eval {
        require Cpanel::HttpUtils::Config::Apache;
        Cpanel::HttpUtils::Config::Apache->new();
    };
    return ( 0, { 'message' => $@ } ) if $@;
    my ( $remove_result, $removed_record ) = $transaction->remove_vhosts_by_name( $servername, 'ssl' );
    return ( 0, { 'message' => $removed_record } ) if !$remove_result;
    my ( $result, $msg ) = $transaction->save();
    $transaction->close();

    if ( !$result ) {
        my $locale = Cpanel::Locale->get_handle();
        my $error  = $locale->maketext( 'The system failed to remove the SSL host for “[_1]” because of an error: [_2]', $host, $msg );
        Cpanel::Logger->new()->warn($error);
        return ( $result, { 'message' => $error } );
    }

    # Kick apache
    Cpanel::HttpUtils::ApRestart::BgSafe::restart();

    my $ret    = [];
    my $locale = Cpanel::Locale->get_handle();
    push @$ret, $locale->maketext( 'Deleting the [asis,SSL] host for “[_1]” …', $host );

    require Cpanel::Config::userdata::Utils;
    my @domains = Cpanel::Config::userdata::Utils::get_all_vhost_domains_from_vhost_userdata($vh_ud);

    # This isn’t very race-safe, but it shouldn’t be too bad,
    # and it won’t matter at all once Apache starts using the
    # domain TLS datastore.
    for my $d (@domains) {
        next if !Cpanel::Domain::TLS->has_tls($d);
        my ( undef, $d_pem ) = Cpanel::Domain::TLS->get_tls($d);
        my $dcert_bin = Crypt::Format::pem2der($d_pem);

        if ( $dcert_bin eq $cert_bin ) {
            Cpanel::Domain::TLS::Write->enqueue_unset_tls($d);
        }
    }

    if ( 'nobody' ne $domainowner ) {
        Cpanel::SSLInstall::Propagate::delete( $domainowner, $servername );
    }

    Cpanel::ServerTasks::schedule_task( ['DovecotTasks'], 120, 'build_mail_sni_dovecot_conf', 'reloaddovecot' );

    push @$ret, $locale->maketext('Done.');
    return ( 1, { 'output' => $ret, 'removed_vhost_data' => $removed_record } );
}

# No really better way I found to do this, as loading WHM APIs in whostmgr
# binaries is generally considered harmful.
sub whmhookeddelsslhost {
    my ( $host, $domainowner ) = @_;

    require Cpanel::Hooks;
    my $hook_args = { 'host' => $host, 'domainowner' => $domainowner };
    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => 'SSL::delssl',
            'stage'    => 'pre',
        },
        $hook_args,
    );

    my ( $status, $ret ) = realdelsslhost( $host, $domainowner );

    $hook_args = {
        %$hook_args,
        %$ret,
    };
    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => 'SSL::delssl',
            'stage'    => 'post',
        },
        $hook_args,
    );

    return ( $status, $ret );
}

1;
