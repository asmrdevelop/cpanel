package Whostmgr::API::1::SSL;

# cpanel - Whostmgr/API/1/SSL.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::Imports;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Exception                    ();
use Cpanel::JSON                         ();
use Cpanel::Debug                        ();
use Cpanel::Hooks                        ();
use Cpanel::PIDFile                      ();
use Cpanel::ServerTasks                  ();
use Cpanel::SSL::Utils                   ();
use Cpanel::ArrayFunc::Uniq              ();
use Cpanel::SafeRun::Object              ();
use Cpanel::SSLInstall                   ();
use Cpanel::SSL::Auto::Config            ();
use Cpanel::SSL::Auto::Config::Read      ();
use Cpanel::SSL::Auto::Loader            ();
use Cpanel::SSL::Domain                  ();
use Cpanel::Hostname                     ();
use Whostmgr::ACLS                       ();
use Whostmgr::AcctInfo::Owner            ();
use Whostmgr::DiskUsage                  ();
use Whostmgr::SSL                        ();
use Cpanel::NAT                          ();
use Whostmgr::API::1::Utils              ();
use Whostmgr::API::1::Data::Filter       ();
use Cpanel::MailUtils::SNI               ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::AdvConfig::dovecot::utils    ();
use Cpanel::Daemonizer::Tiny             ();
use Cpanel::Features::Check              ();
use Cpanel::Validate::Username           ();
use Cpanel::SSL::Auto::Exclude::Get      ();
use Cpanel::SSL::Auto::Exclude::Set      ();
use Cpanel::Domain::Owner                ();

use Digest::MD5 ();    # for ssl storage until it can be converted to use Cpanel::Hash

use constant NEEDS_ROLE => {
    add_autossl_user_excluded_domains    => undef,
    disable_autossl                      => undef,
    disable_mail_sni                     => undef,
    enable_mail_sni                      => undef,
    enqueue_deferred_ssl_installations   => undef,
    fetch_service_ssl_components         => undef,
    fetch_ssl_certificates_for_fqdns     => undef,
    fetch_ssl_vhosts                     => undef,
    fetch_vhost_ssl_components           => undef,
    fetchcrtinfo                         => undef,
    fetchsslinfo                         => undef,
    generatessl                          => undef,
    get_autossl_check_schedule           => undef,
    get_autossl_log                      => undef,
    get_autossl_logs_catalog             => undef,
    get_autossl_metadata                 => undef,
    get_autossl_problems_for_domain      => undef,
    get_autossl_problems_for_user        => undef,
    get_autossl_providers                => undef,
    get_autossl_user_excluded_domains    => undef,
    get_best_ssldomain_for_service       => undef,
    install_service_ssl_certificate      => undef,
    installssl                           => undef,
    delete_ssl_vhost                     => undef,
    is_sni_supported                     => undef,
    listcrts                             => undef,
    mail_sni_status                      => undef,
    rebuild_mail_sni_config              => undef,
    rebuildinstalledssldb                => undef,
    rebuilduserssldb                     => undef,
    remove_autossl_user_excluded_domains => undef,
    reset_autossl_provider               => undef,
    reset_service_ssl_certificate        => undef,
    set_autossl_metadata                 => undef,
    set_autossl_metadata_key             => undef,
    set_autossl_provider                 => undef,
    set_autossl_user_excluded_domains    => undef,
    start_autossl_check_for_all_users    => undef,
    start_autossl_check_for_one_user     => undef,
};

use Try::Tiny;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::SSL - WHM API functions to manage SSL certificates on the server.

=head1 Methods

=cut

sub _get_child_account_error_payload ( $metadata, $username ) {

    require Cpanel::Config::LoadCpUserFile;

    my $user_conf = Cpanel::Config::LoadCpUserFile::load_or_die($username);

    if ( $user_conf->child_workloads() ) {

        require Cpanel::APICommon::Persona;
        my ( $msg, $payload ) = Cpanel::APICommon::Persona::get_whm_expect_parent_error_pieces( undef, $username );
        $metadata->set_not_ok($msg);

        return $payload;
    }

    return;
}

sub rebuilduserssldb {
    my ( $args, $metadata ) = @_;

    my $user = defined $args->{'user'} ? $args->{'user'} : $ENV{'REMOTE_USER'};

    if ( $user ne $ENV{'REMOTE_USER'} && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user ) ) {
        require Cpanel::Locale;
        my $locale = Cpanel::Locale->get_handle();
        $metadata->{'reason'} = $locale->maketext( 'You do not own a user “[_1]”.', $user );
        $metadata->{'result'} = 0;
        return;
    }

    eval 'require Cpanel::SSLStorage::User' if !$INC{'Cpanel/SSLStorage/User.pm'};
    return _rebuild( $metadata, Cpanel::SSLStorage::User->new( user => $user ) );
}

sub rebuildinstalledssldb {
    my ( $args, $metadata ) = @_;

    @{$metadata}{ 'result', 'reason', 'warnings' } = ( 1, 'OK', ['This function is now a no-op.'] );
    return;
}

sub _rebuild {
    my ( $metadata, $ok, $sslstorage ) = @_;

    if ( !$ok ) {
        @{$metadata}{ 'result', 'reason' } = ( 0, $sslstorage );
        return;
    }

    my $retval;
    ( $ok, $retval ) = $sslstorage->rebuild_records();
    if ( !$ok ) {
        @{$metadata}{ 'result', 'reason' } = ( 0, $retval );
        return;
    }

    @{$metadata}{ 'result', 'reason' } = qw(1 OK);
    return { 'records' => $retval };
}

sub generatessl ( $args, $metadata, @ ) {

    my $sslinfo = Whostmgr::SSL::generate(%$args);

    foreach my $code_element (qw(fglob uniq wildcard_safe file_test locale MagicRevision)) {
        delete $sslinfo->{$code_element};
    }
    foreach my $element ( keys %{$sslinfo} ) {
        delete $sslinfo->{$element} if ref $element eq 'CODE';
    }

    $metadata->{'result'} = $sslinfo->{'status'} ? 1 : 0;
    $metadata->{'reason'} = $sslinfo->{'message'} || ( $sslinfo->{'status'} ? 'OK' : 'Failed to generate SSL information.' );
    return if !$sslinfo->{'status'};
    delete $sslinfo->{'status'};
    delete $sslinfo->{'message'};
    return $sslinfo;
}

sub fetch_service_ssl_components {
    my ( $args, $metadata ) = @_;

    require Cpanel::SSLCerts;
    my @services;

    foreach my $service ( Cpanel::SSLCerts::available_services() ) {
        my $file_ref = Cpanel::SSLCerts::fetchSSLFiles( 'service' => $service );

        my $cert = $file_ref->{'crt'};
        my $key  = $file_ref->{'key'};
        my $cab  = $file_ref->{'cab'};

        my ( $ok, $cert_info ) = _fetch_cert_info($cert);

        my $service_info = {
            'service'          => $service,
            'certificate'      => $cert,
            'key'              => $key,
            'cabundle'         => $cab,
            'certificate_info' => $ok ? $cert_info : undef,
        };

        push @services, $service_info;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return { 'services' => \@services };

}

sub install_service_ssl_certificate {
    my ( $args, $metadata ) = @_;

    my $service  = $args->{'service'};
    my $cert     = $args->{'crt'};
    my $key      = $args->{'key'};
    my $cabundle = $args->{'cabundle'};

    if ( !$cabundle ) {
        require Cpanel::SSLInfo;
        my $cab = ( Cpanel::SSLInfo::fetchcabundle($cert) )[2];
        $cabundle = $cab if Cpanel::SSLInfo::is_ssl_payload($cab);
    }

    # Execute Pre hook
    my ( $status, $message ) = Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => 'SSL::install_service_ssl_certificate',
            'stage'    => 'pre',
            'blocking' => 1,
        },
        {
            'service'  => $service,
            'crt'      => $cert,
            'key'      => $key,
            'cabundle' => $cabundle,
        }
    );

    ( $status, $message ) = Whostmgr::DiskUsage::verify_partitions() if $status;

    if ($status) {
        require Cpanel::SSLCerts;
        ( $status, $message ) = Cpanel::SSLCerts::installSSLFiles( 'service' => $service, 'crt' => $cert, 'key' => $key, 'cab' => $cabundle, 'quiet' => 1 );
    }

    # Execute Post hook if it succeeded
    if ($status) {
        ( $status, $message ) = Cpanel::Hooks::hook(
            {
                'category' => 'Whostmgr',
                'event'    => 'SSL::install_service_ssl_certificate',
                'stage'    => 'post',
                'blocking' => 1,
            },
            {
                'service'  => $service,
                'crt'      => $cert,
                'key'      => $key,
                'cabundle' => $cabundle,
            }
        );
    }

    @{$metadata}{qw( result reason )} = $status ? (qw(1 OK)) : ( 0, $message );
    return if !$status;
    return _restart_and_return_service_cert_status( $service, $cert );
}

sub reset_service_ssl_certificate {
    my ( $args, $metadata ) = @_;

    my $service = $args->{'service'};

    my ( $status, $message ) = Whostmgr::DiskUsage::verify_partitions();

    require Cpanel::SSLCerts;
    if ($status) {
        #
        # createDefaultSSLFiles does everything that resetSSLFiles does
        # so there is no need to run both.
        #
        ( $status, $message ) = Cpanel::SSLCerts::createDefaultSSLFiles( 'service' => $service, 'quiet' => 1 );
    }

    @{$metadata}{qw( result reason )} = $status ? (qw(1 OK)) : ( 0, $message );
    return if !$status;
    return _restart_and_return_service_cert_status( $service, Cpanel::SSLCerts::fetchSSLFiles( 'service' => $service )->{'crt'} );
}

sub _restart_and_return_service_cert_status {
    my ( $service, $cert ) = @_;

    my ( $ok, $cert_info ) = _fetch_cert_info($cert);
    _handle_restarts($service);

    require Cpanel::SSLCerts;
    return {
        'service'             => $service,
        'certificate'         => $cert,
        'certificate_info'    => $ok ? $cert_info : undef,
        'service_description' => Cpanel::SSLCerts::rSERVICES()->{$service}{'description'},
    };
}

sub _handle_restarts {
    my ($service) = @_;

    # We use the same certificates for HTTPS service (formerly proxy) subdomains as we do for
    # cpsrvd, so ensure that that the configuration refers to the correct
    # one of cpanel.pem or mycpanel.pem.
    return if grep { $service eq $_ } qw{caldav_apns carddav_apns};
    if ( $service eq 'cpanel' ) {
        try {
            Cpanel::ServerTasks::queue_task( [ 'CpServicesTasks', 'ApacheTasks' ], 'build_apache_conf', 'apache_restart --force', 'restartsrv cpsrvd', 'restartsrv cpdavd' );
        }
        catch {
            Cpanel::Debug::log_warn($_);
        };
    }
    elsif ( $service eq 'mail_apns' || $service eq 'dovecot' ) {
        Cpanel::SafeRun::Object->new_or_die( 'program' => '/usr/local/cpanel/scripts/builddovecotconf' );    # TODO : taskqueue
        try {
            Cpanel::ServerTasks::queue_task( [ 'DovecotTasks', 'CpServicesTasks' ], 'restartdovecot', 'restartsrv tailwatchd' );
        }
        catch {
            Cpanel::Debug::log_warn($_);
        };
    }
    else {
        try {
            Cpanel::ServerTasks::queue_task( ['CpServicesTasks'], "restartsrv $service" );
        }
        catch {
            Cpanel::Debug::log_warn($_);
        };
    }

    return;
}

sub fetchcrtinfo {
    my ( $args, $metadata ) = @_;
    my $id   = $args->{'id'};
    my $user = $args->{'user'} || $ENV{'REMOTE_USER'};

    require Cpanel::Locale;
    if ( $user ne $ENV{'REMOTE_USER'} && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user ) ) {
        my $locale = Cpanel::Locale->get_handle();
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'You do not own a user “[_1]”.', $user );
        return;
    }

    if ( length $id ) {
        require Cpanel::SSLInfo;
        my ( $ok, $payload ) = Cpanel::SSLInfo::fetch_crt_info( $id, $user );

        if ($ok) {
            @{$metadata}{qw(result reason)} = ( 1, 'OK' );
            return $payload;
        }
        else {
            @{$metadata}{qw(result reason)} = ( 0, $payload );
        }
    }
    else {
        my $locale = Cpanel::Locale->get_handle();
        @{$metadata}{qw(result reason)} = ( 0, $locale->maketext( 'The “[_1]” parameter is missing.', 'id' ) );
    }

    return;
}

sub fetch_ssl_certificates_for_fqdns {
    my ( $args, $metadata ) = @_;

    #For parity with (older) APIs on the cPanel side.
    my @req_domains = split m<[,;\s]+>, Whostmgr::API::1::Utils::get_length_required_argument( $args, 'domains' );

    #Always check the current reseller’s SSL resources.
    my @users = ( $ENV{'REMOTE_USER'} );

    require Cpanel::AcctUtils::DomainOwner::BAMP;

    my $domain_owner;
    for my $domain (@req_domains) {
        $domain_owner = Cpanel::AcctUtils::DomainOwner::BAMP::getdomainownerBAMP( $domain, { 'default' => '' } );
        last if $domain_owner;
    }

    # “system” doesn’t have SSLStorage, but that user’s certificates are
    # saved in root’s SSLStorage. So if the caller has root privs they’ll
    # see those certs already.
    $domain_owner = q<> if $domain_owner && $domain_owner eq 'system';

    if ( $domain_owner && ( $domain_owner ne $ENV{'REMOTE_USER'} ) ) {
        require Whostmgr::AcctInfo::Owner;
        if ( Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $domain_owner ) ) {

            #Search the domain owner’s SSL resources first.
            unshift @users, $domain_owner;
        }
    }

    require Cpanel::SSL::Search;

    # fetch_users_certificates_for_fqdns only searches the users ssl storage
    # in @users so its safe to exclude 'system' as it means it won't search
    # an invalid user.
    my @certs_return = Cpanel::SSL::Search::fetch_users_certificates_for_fqdns(
        users   => \@users,
        domains => \@req_domains,
    );

    for my $c (@certs_return) {

        #For parity with older APIs in this module.
        @{$c}{ 'crt', 'cab' } = delete @{$c}{ 'certificate', 'ca_bundle' };
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { payload => \@certs_return };
}

sub fetchsslinfo {
    my ( $args, $metadata ) = @_;
    my $domain  = $args->{'domain'};
    my $crtdata = $args->{'crtdata'};

    my $sslinfo;
    my $result;
    my $reason;

    # Validate the inputs
    if ( !length $crtdata && !length $domain ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'No certificate data or domain supplied.';
        return;
    }

    # Fetch the information if possible
    $sslinfo = Whostmgr::SSL::reseller_aware_fetch_sslinfo( $domain, $crtdata );

    if ( !length keys %{$sslinfo} ) {
        $result = 0;
        $reason = ( $domain ? 'Unable to fetch SSL info for domain: ' . $domain : 'Unable to fetch SSL info for the provided certificate' );
    }
    else {
        $result = $sslinfo->{'status'};
        $reason = $sslinfo->{'statusmsg'};
        delete $sslinfo->{'status'};
        delete $sslinfo->{'statusmsg'};
    }

    $metadata->{'result'} = $result ? 1 : 0;
    if ($result) {
        $metadata->{'reason'} = 'OK';
        if ( !$sslinfo->{'crt'} && $reason ) {
            $metadata->{'output'}{'messages'} = [$reason];
        }
    }
    else {
        $metadata->{'reason'} = $reason || 'Failed to retrieve SSL information.';
    }

    return if !$result;
    return $sslinfo;
}

sub listcrts {
    my ( $args, $metadata ) = @_;

    my $user = $args->{'user'} || $ENV{'REMOTE_USER'};
    if ( $user && $user ne $ENV{'REMOTE_USER'} && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user ) ) {
        require Cpanel::Locale;
        my $locale = Cpanel::Locale->get_handle();
        @{$metadata}{ 'result', 'reason' } = ( 0, $locale->maketext( 'You do not own a user “[_1]”.', $user ) );
        return;
    }

    my ( $ok, $rsd_ar ) = Whostmgr::SSL::list_cert_domains_with_owners(
        user       => $user,
        registered => $args->{'registered'},
    );

    if ($ok) {
        @{$metadata}{ 'result', 'reason' } = ( 1, 'OK' );
        return { 'crt' => $rsd_ar };
    }

    @{$metadata}{ 'result', 'reason' } = ( 0, $rsd_ar );
    return;
}

sub enqueue_deferred_ssl_installations ( $args, $metadata, @ ) {
    require Cpanel::SSLInstall::SubQueue::Adder;
    require Cpanel::Config::userdata::Load;
    require Cpanel::ServerTasks;

    my @usernames = Whostmgr::API::1::Utils::get_length_required_arguments( $args, 'username' );

    Cpanel::Validate::Username::validate_or_die($_) for @usernames;

    my @miscount;
    my %other_args;

    for my $argname (qw( vhost_name key crt )) {
        my @values = Whostmgr::API::1::Utils::get_length_required_arguments( $args, $argname );
        push @miscount, $argname if @values != @usernames;
        $other_args{$argname} = \@values;
    }

    # There’s no particular reason why a vhost name need be a domain name,
    # but as of v88 all vhost names are always the httpd vhost ServerName.
    require Cpanel::Validate::Domain;
    Cpanel::Validate::Domain::valid_wild_domainname_or_die($_) for @{ $other_args{'vhost_name'} };

    my @cabs = Whostmgr::API::1::Utils::get_arguments( $args, 'cab' );

    push @miscount, 'cab' if @cabs != @usernames;

    die "Mismatch count: username @miscount" if @miscount;

    $other_args{'cab'} = \@cabs;

    require Cpanel::Validate::PEM;
    require Crypt::Format;

    for my $param (qw( key crt cab )) {
        my $values_ar = $other_args{$param};

        my $i;

        try {
            $i = 0;

            while ( $i <= $#$values_ar ) {
                next if $param eq 'cab' && !length $values_ar->[$i];

                my @chain = Crypt::Format::split_pem_chain( $values_ar->[$i] );
                Cpanel::Validate::PEM::validate_or_die($_) for @chain;
            }
            continue {
                $i++;
            }
        }
        catch {
            my $idx = 1 + $i;
            die "“$param” #$idx is invalid: $_";
        };
    }

    # It would be nice to validate the SSL parameters here,
    # but for now this is not implemented. We do at least
    # validate that the given username matches the vhost name, though.
    for my $i ( 0 .. $#usernames ) {
        my $username   = $usernames[$i];
        my $vhost_name = $other_args{'vhost_name'}[$i];

        Cpanel::Config::userdata::Load::user_has_domain( $username, $vhost_name ) or do {
            die locale()->maketext( '“[_1]” does not own a web virtual host named “[_2]”.', $username, $vhost_name );
        };
    }

    for my $i ( 0 .. $#usernames ) {
        my $username   = $usernames[$i];
        my $vhost_name = $other_args{'vhost_name'}[$i];

        Cpanel::SSLInstall::SubQueue::Adder->add(
            $vhost_name,
            [
                $username,
                ( map { $_->[$i] } @other_args{ 'key', 'crt' } ),
                $cabs[$i],
            ],
        );
    }

    Cpanel::ServerTasks::schedule_task( ['SSLTasks'], 10, 'install_from_subqueue' );

    $metadata->set_ok();

    return;
}

sub installssl {
    my ( $args, $metadata ) = @_;

    $args->{'ip'} = Cpanel::NAT::get_local_ip( $args->{'ip'} );

    _do_hook( $args, 'SSL::installssl', 'pre' );

    my $sslinfo = Cpanel::SSLInstall::install_or_do_non_sni_update(
        ( map { $_ => $args->{$_} } qw(domain ip crt key cab ) ),
        disclose_user_data => Whostmgr::ACLS::hasroot(),
    );

    _do_hook( $args, 'SSL::installssl', 'post' );

    $metadata->{'result'} = $sslinfo->{'status'} ? 1 : 0;
    $metadata->{'reason'} = $sslinfo->{'message'} || ( $sslinfo->{'status'} ? 'OK' : 'Failed to install SSL information.' );
    if ( length $sslinfo->{'html'} ) {
        $metadata->{'output'}->{'raw'} = $sslinfo->{'html'};
    }

    if ( defined $sslinfo->{'aliases'} && ref $sslinfo->{'aliases'} ne 'ARRAY' ) {
        $sslinfo->{'aliases'} = [ split m{\s+}, $sslinfo->{'aliases'} ];
    }

    return if !$sslinfo->{'status'};

    $sslinfo->{'ip'} = Cpanel::NAT::get_public_ip( $sslinfo->{'ip'} );

    return $sslinfo;
}

sub delete_ssl_vhost {
    my ( $args, $metadata ) = @_;

    my $host = Whostmgr::API::1::Utils::get_required_argument( $args, 'host' );

    my $domainowner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $host, { default => 'nobody' } );

    if ( !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $domainowner ) && $domainowner ne $ENV{'REMOTE_USER'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Sorry you do not have access to the host $host";
        return;
    }

    require Cpanel::SSLDelete;
    my ( $status, $ret ) = Cpanel::SSLDelete::whmhookeddelsslhost( $host, $domainowner );

    $metadata->{'result'} = $status;
    $metadata->{'reason'} = $status ? 'OK' : 'Failed to remove SSL vhost.';

    return $ret;
}

#----------------------------------------------------------------------

#Overridden in tests
sub _get_pid {
    my ($pidfile) = @_;

    return Cpanel::PIDFile->get_pid($pidfile);
}

sub _run_autossl_script_and_finish {
    my ( $metadata, @exec_args ) = @_;

    require Cpanel::SSL::Auto::Check;
    my $pidfile;
    if ( grep { $_ eq '--user' } @exec_args ) {
        $pidfile = Cpanel::SSL::Auto::Check::generate_pidfile_for_username( $exec_args[-1] );
    }
    else {
        $pidfile = $Cpanel::SSL::Auto::Check::PID_FILE;
    }

    my $old_pid = _get_pid($pidfile);
    if ( $old_pid && kill 'ZERO', $old_pid ) {
        die Cpanel::Exception::create( 'CommandAlreadyRunning', [ pid => $old_pid, file => $pidfile ] );
    }

    #This is done as a fork/exec for two reasons:
    #   - It has to fork() because this is a long-running process.
    #   - The exec() preserves memory by allowing the OS to keep only
    #       what the AutoSSL check logic needs.
    #
    my $pid = Cpanel::Daemonizer::Tiny::run_as_daemon(
        sub {
            my $to_exec = $Cpanel::SSL::Auto::Check::COMMAND;
            exec {$to_exec} $to_exec, @exec_args;
        },
    );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { pid => $pid };
}

sub get_autossl_check_schedule {
    my ( $args, $metadata ) = @_;

    my $return;

    require Cpanel::SSL::Auto::Cron;
    my $ct = Cpanel::SSL::Auto::Cron->get_entry();
    if ($ct) {
        require Schedule::Cron::Events;
        require Cpanel::Time::ISO;
        require Time::Local;

        my $sched      = Schedule::Cron::Events->new( $ct->dump() );
        my @smhdmy     = $sched->nextEvent();
        my $next_epoch = 'Time::Local'->can('timelocal')->(@smhdmy);

        $return = {
            cron      => [ split m<\s+>, $ct->datetime() ],
            next_time => 'Cpanel::Time::ISO'->can('unix2iso')->($next_epoch),
        };
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return $return;
}

sub _check_autossl_enabled {

    # check and see if autossl is enabled, if not throw exception
    my $conf = Cpanel::SSL::Auto::Config::Read->new();

    if ( !length $conf->get_provider() ) {
        die Cpanel::Exception->create('This system has [asis,AutoSSL] disabled.');
    }

    return;
}

sub start_autossl_check_for_all_users {
    my ( $args, $metadata ) = @_;

    _check_autossl_enabled();

    return _run_autossl_script_and_finish( $metadata, '--all' );
}

sub start_autossl_check_for_one_user {
    my ( $args, $metadata ) = @_;

    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );

    Cpanel::Validate::Username::user_exists_or_die($username);

    _check_autossl_enabled();

    #Check to see if AutoSSL is enabled for the passed user
    if ( !Cpanel::Features::Check::check_feature_for_user( $username, 'autossl' ) ) {
        die Cpanel::Exception->create( 'The user “[_1]” does not have the [asis,AutoSSL] feature enabled.', [$username] );
    }

    my $payload = _get_child_account_error_payload( $metadata, $username );
    return $payload if $payload;

    return _run_autossl_script_and_finish(
        $metadata,
        '--user' => $username,
    );
}

sub set_autossl_provider {
    my ( $args, $metadata ) = @_;

    my $provider = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'provider' );

    my $conf = Cpanel::SSL::Auto::Config->new();

    _activate_autossl( $conf, $provider, $args );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

sub _activate_autossl {
    my ( $conf, $provider, $args_hr ) = @_;

    require Cpanel::SSL::Auto;
    require Cpanel::SSL::Auto::Cron;
    my %new_props;

    for my $key ( keys %$args_hr ) {
        next if $key !~ m<\Ax_(.*)>;
        $new_props{$1} = $args_hr->{$key};
    }

    if (%new_props) {
        Cpanel::SSL::Auto::export_provider_properties( $provider, $conf, %new_props );
    }
    else {

        # If provider the requires parameter (x_terms_of_service_accepted), but it isn't supplied,
        # throw exception

        my $ns                 = Cpanel::SSL::Auto::Loader::get_and_load($provider);
        my %current_properties = $ns->PROPERTIES();

        # has terms of service
        # no new terms_of_service_accepted passed in, and the current one is outdated
        if ( $current_properties{'terms_of_service'} && $current_properties{'terms_of_service_accepted'} ne $current_properties{'terms_of_service'} ) {

            die Cpanel::Exception->create( 'In order to activate the “[_1]” [asis,AutoSSL] provider, you must accept the current terms of service ([_2]) by passing the encoded url as the “[asis,x_terms_of_service_accepted]” parameter. The AutoSSL provider cannot be activated.', [ $provider, $current_properties{'terms_of_service'} ] );

        }
    }

    $conf->set_provider_property( $provider, $_, $new_props{$_} ) for keys %new_props;

    $conf->set_provider($provider);

    $conf->save_and_close();

    Cpanel::SSL::Auto::Cron->ensure_that_entry_exists();

    return;
}

sub reset_autossl_provider {
    my ( $args, $metadata ) = @_;

    my $provider = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'provider' );

    my $conf = Cpanel::SSL::Auto::Config->new();

    my $ns = Cpanel::SSL::Auto::Loader::get_and_load($provider);
    $ns->RESET();

    my @properties = keys %{ { $conf->get_provider_properties($provider) } };
    for my $property (@properties) {
        $conf->unset_provider_property( $provider, $property );
    }

    _activate_autossl( $conf, $provider, $args );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

sub get_autossl_providers {
    my ( $args, $metadata ) = @_;

    require Cpanel::SSL::Auto;
    my @data = Cpanel::SSL::Auto::get_all_provider_info();

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { payload => \@data };
}

sub disable_autossl {
    my ( $args, $metadata ) = @_;

    require Cpanel::SSL::Auto::Cron;
    my $conf = Cpanel::SSL::Auto::Config->new();

    $conf->disable();

    $conf->save_and_close();

    Cpanel::SSL::Auto::Cron->delete_entry();

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

sub get_autossl_logs_catalog {
    my ( $args, $metadata ) = @_;

    require Cpanel::SSL::Auto::Log;

    my @logs = Cpanel::SSL::Auto::Log->get_catalog();

    # We have no reason for now to expose these to API callers.
    delete @{$_}{ 'upid', 'original_process_is_complete' } for @logs;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { payload => \@logs };
}

sub get_autossl_log {
    my ( $args, $metadata ) = @_;

    my @read_args = map { Whostmgr::API::1::Utils::get_length_required_argument( $args, $_ ); } qw( start_time );

    require Cpanel::SSL::Auto::Log;
    my $entries_ar = Cpanel::SSL::Auto::Log->read(@read_args);

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { payload => $entries_ar };
}

sub set_autossl_metadata_key {
    my ( $args, $metadata ) = @_;

    my $key   = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'key' );
    my $value = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'value' );

    my $conf = Cpanel::SSL::Auto::Config->new();
    my $md   = $conf->get_metadata();
    $md->{$key} = $value;
    $conf->set_metadata(%$md);
    $conf->save_and_close();

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

sub get_autossl_metadata {
    my ( $args, $metadata ) = @_;

    my $conf = Cpanel::SSL::Auto::Config::Read->new();
    my $md   = $conf->get_metadata();

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { payload => $md };
}

sub set_autossl_metadata {
    my ( $args, $metadata ) = @_;

    my $md_json = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'metadata_json' );
    my $md      = Cpanel::JSON::Load($md_json);

    my $conf = Cpanel::SSL::Auto::Config->new();
    $conf->set_metadata(%$md);
    $conf->save_and_close();

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

#----------------------------------------------------------------------

=head2 B<enable_mail_sni>

Enables SNI for mail services on the specified domains.

See L<_set_main_sni_status_for_domain> for more details.

=cut

sub enable_mail_sni {
    my ( $args, $metadata ) = @_;

    $args->{'enable'} = 1;
    return _set_main_sni_status_for_domain( $args, $metadata );
}

=head2 B<disable_mail_sni>

This call now always fails (as of 11.60).

=cut

sub disable_mail_sni {

    die 'cPanel & WHM no longer allows mail SNI to be disabled.';
}

=head2 B<mail_sni_status>

Returns a hashref detailing whether or not SNI for mail services is enabled for the specified domain. As of 11.60, it will always be enabled.

B<Input>: the domain to check

    {
        'domain' => 'cptest.tld',
    }

B<Output>:

    {
        'enabled' => 1,     #it’s always 1 as of 11.60
    }

=cut

sub mail_sni_status {
    my ( $args, $metadata ) = @_;

    my $domain      = $args->{'domain'};
    my $domainowner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'default' => 'nobody' } );
    if ( $domainowner ne $ENV{'REMOTE_USER'} && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $domainowner ) ) {
        require Cpanel::Locale;
        my $locale = Cpanel::Locale->get_handle();
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'You do not own the domain “[_1]”.', $domain );
        return;
    }

    @{$metadata}{qw(result reason)} = qw(1 OK);

    $metadata->{'warnings'} = ['Mail SNI is always enabled now.'];

    return { 'enabled' => 1 };
}

=head2 B<rebuild_mail_sni_config>

Rebuilds the SNI configuration file.

B<Input>: An optional argument can be passed to 'reload' the Dovecot service once the configuration files
have been rebuilt:

    {
        'reload_dovecot' => 1,
    }

B<Output>: When run as root, it returns details in regards to what configuration files were rebuilt:

    {
        'success' => 1,
        'configs_built' => [
            '/etc/dovecot/sni.conf',
        ],
    },

Otherwise, simply returns a success value indicating whether or not the operation was successful:

    {
        'success' => 1
    }

=cut

sub rebuild_mail_sni_config {
    my ( $args, $metadata ) = @_;

    my $dovecot_conf = Cpanel::AdvConfig::dovecot::utils::find_dovecot_sni_conf();
    my $cpconf       = Cpanel::Config::LoadCpConf::loadcpconf();

    my $output;
    $output->{'configs_built'} = [];

    eval {
        if ( Cpanel::MailUtils::SNI->rebuild_dovecot_sni_conf() ) {
            push @{ $output->{'configs_built'} }, $dovecot_conf;
            if ( $args->{'reload_dovecot'} ) {
                require Whostmgr::Services::Load;
                Whostmgr::Services::Load::reload_service('dovecot');
            }
        }
    };
    if ( my $error = $@ ) {
        require Cpanel::Locale;
        my $locale = Cpanel::Locale->get_handle();
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'The system failed to rebuild the Mail SNI configuration. Error: “[_1]”.', $error );
        return;
    }

    $output->{'success'} = 1;
    delete $output->{'configs_built'} if !Whostmgr::ACLS::hasroot();
    @{$metadata}{qw(result reason)} = qw(1 OK);

    return $output;
}

=head2 B<_set_main_sni_status_for_domain>

Helper method that sets the SNI status as specified.

B<Input>: The domains to alter, and the 'enable' status to set.

    {
        'domain' => 'cptest.tld',
        'domain-1' => 'cptest2.tld',
        ...
        'domain-n' => 'cptestn.tld',
        'enable' => 1 (or 0 to disable),
    }

B<Output>:

    {
        'updated_domains' => {
            ...
            'cptest1.tld' => hashref to the domain's SSL userdata if run as root. If not, this is set to a '1'.
            ...
        },
        'failed_domains' => {
            ...
            'cptest2.tld' => 'reason for failure',
            ...
        }
    }

=cut

sub _set_main_sni_status_for_domain {
    my ( $args, $metadata ) = @_;
    @{$metadata}{qw(result reason)} = qw(1 OK);

    require Cpanel::Locale;
    my $locale  = Cpanel::Locale->get_handle();
    my $domains = _parse_domains($args);
    if ( not scalar @{$domains} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('No domains specified.');
        return;
    }

    my $enable = delete $args->{'enable'} ? 1 : 0;
    my $output;
    $output->{'failed_domains'}  = {};
    $output->{'updated_domains'} = {};

    foreach my $domain ( @{$domains} ) {
        my $domainowner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'default' => 'nobody' } );
        if ( $domainowner ne $ENV{'REMOTE_USER'} && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $domainowner ) ) {
            $output->{'failed_domains'}->{$domain} = $locale->maketext( 'You do not own the domain “[_1]”.', $domain );
            next;
        }

        #There’s no need to do anything here anymore.
    }

    $metadata->{'warnings'} = ['Mail SNI is always enabled now.'];

    return $output;
}

sub is_sni_supported {
    my ( $args, $metadata ) = @_;

    @{$metadata}{qw(result reason)} = qw(1 OK);

    $metadata->{'warnings'} = ['SNI is always supported now.'];

    return { sni => 1 };
}

sub fetch_ssl_vhosts {
    my ( $args, $metadata ) = @_;

    my ( $result, $payload ) = Whostmgr::SSL::fetch_ssl_vhosts( aliases => 1 );

    if ( !$result ) {
        @{$metadata}{qw(result reason)} = ( 0, $payload );
        return;
    }

    for my $vhost_data (@$payload) {
        my $aliases_ar = delete $vhost_data->{'aliases'} || [];
        $vhost_data->{'servername'} = delete $vhost_data->{'sslhost'};
        my @domains = sort( Cpanel::ArrayFunc::Uniq::uniq( ( $vhost_data->{'servername'}, @$aliases_ar ) ) );
        $vhost_data->{'domains'} = \@domains;

        delete @{$vhost_data}{qw( hasssl sharedip )};
    }

    @{$metadata}{qw(result reason)} = qw(1 OK);

    return { vhosts => $payload };
}

sub fetch_vhost_ssl_components {
    my ( $args, $metadata, $api_args ) = @_;

    my $servername;

    my @filters = Whostmgr::API::1::Data::Filter::get_filters($api_args);

    for my $filter (@filters) {
        my ( $field, $type, $term ) = @$filter;
        if ( ( $field eq 'servername' ) && ( $type eq 'eq' ) ) {
            $servername = $term;
            Whostmgr::API::1::Data::Filter::mark_filters_done( $api_args, $filter );
            last;
        }
    }

    my ( $result, $payload ) = Whostmgr::SSL::fetch_vhost_ssl_components( servername => $servername );
    if ( !$result ) {
        @{$metadata}{qw(result reason)} = ( 0, $payload );
        return;
    }

    if ($servername) {
        Whostmgr::API::1::Data::Filter::set_filtered_count( $api_args, $payload->{'ssl_vhosts_count'} );
    }

    if ( !$result ) {
        @{$metadata}{qw(result reason)} = ( 0, $payload );
        return;
    }

    @{$metadata}{qw(result reason)} = qw(1 OK);

    return { components => $payload->{'components'} };
}

=head2 B<get_best_ssldomain_for_service>

Returns a hashref detailing the ssl name and status of a service.

B<Input>: the service to get the best ssl domain for.

    {
        'service' => 'cpanel|ftp|dovecot|exim',
    }

B<Output>:

    {
        'cert_valid_not_after'   => UNIXTIME (or undef),
        'ssldomain'              => DOMAIN,
        'is_currently_valid'     => 1 (or 0),
        'is_wild_card'           => 1 (or 0),
        'cert_match_method'      => 'exact-wildcard|exact|none|localdomain_on_cert|www-wildcard|mail-wildcard|localdomain_on_cert-mail-wildcard|localdomain_on_cert-www-wildcard|hostname',
            none — No domain matches the certificate.
            exact — The domain exactly matched the certificate.
            exact-wildcard — The domain exactly matched the domain of a wildcard certificate.
            mail-wildcard — The mail subdomain of the domain matched the domain of the wildcard certificate.
            www-wildcard — The www subdomain of the domain matched the domain of the wildcard certificate.
            hostname-wildcard — The hostname's domain matched the domain of the wildcard certificate.
            hostname — The hostname matched the domain of the certificate.
            localdomain_on_cert-mail-wildcard — Any mail subdomain of any domain on the server matches the certificate.
            localdomain_on_cert-www-wildcard — Any www subdomain of any domain on the server matches the certificate.
            localdomain_on_cert — Any domain on the server matches the certificate.
        'is_self_signed'         => 1 (or 0),
        'ssldomain_matches_cert' => 1 (or 0)
    }

=cut

sub get_best_ssldomain_for_service {
    my ( $args, $metadata ) = @_;
    my $service = Whostmgr::API::1::Utils::get_required_argument( $args, 'service' );
    my ( $ssl_domain_info_status, $ssl_domain_info ) = Cpanel::SSL::Domain::get_best_ssldomain_for_object( Cpanel::Hostname::gethostname(), { 'service' => $service } );

    if ( !$ssl_domain_info_status ) {
        @{$metadata}{qw(result reason)} = ( $ssl_domain_info_status, $ssl_domain_info );
        return;
    }
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return $ssl_domain_info;
}

sub _fetch_cert_info {
    my ($cert) = @_;

    my ( $ok, $parse ) = Cpanel::SSL::Utils::parse_certificate_text($cert);
    if ($ok) {
        return (
            $ok,
            {
                'issuer.commonName'       => $parse->{'issuer'}{'commonName'},
                'issuer.organizationName' => $parse->{'issuer'}{'organizationName'},
                'issuer_text'             => join( "\n", map { @$_ } @{ $parse->{'issuer_list'} } ),

                %{$parse}{
                    'key_algorithm',
                    'modulus',
                    'modulus_length',
                    'ecdsa_curve_name',
                    'ecdsa_public',
                    'not_before',
                    'not_after',
                    'domains',
                    'is_self_signed',
                },
            }
        );
    }
    return ( $ok, $parse );
}

=head2 B<get_autossl_user_excluded_domains>

This function gets the AutoSSL excluded domains for a user.

B<Input>:

    {
        username => 'username'
    }

B<Output>:

    [
      { 'excluded_domain' => 'domain1.tld' },
      { 'excluded_domain' => 'domain2.tld' },
      ...
    },

=cut

sub get_autossl_user_excluded_domains {
    my ( $args, $metadata ) = @_;

    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );

    Cpanel::Validate::Username::user_exists_or_die($username);

    my $payload = _get_child_account_error_payload( $metadata, $username );
    return $payload if $payload;

    my @domains = Cpanel::SSL::Auto::Exclude::Get::get_user_excluded_domains($username);

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { payload => [ map { { 'excluded_domain' => $_ } } @domains ] };
}

=head2 B<set_autossl_user_excluded_domains>

This function sets the AutoSSL excluded domains for a user.

B<Input>: domains is passed in as an array of 'domain'

    whmapi1 set_autossl_user_excluded_domains username=aardvark domain=ants.tld domain=tasty.tld

B<Output>:

    None.

=cut

sub set_autossl_user_excluded_domains {
    my ( $args, $metadata ) = @_;

    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );
    my $domains  = _parse_domains($args);
    Cpanel::Validate::Username::user_exists_or_die($username);

    my $payload = _get_child_account_error_payload( $metadata, $username );
    return $payload if $payload;

    Cpanel::SSL::Auto::Exclude::Set::set_user_excluded_domains( 'user' => $username, 'domains' => $domains );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

=head2 B<add_autossl_user_excluded_domains>

This function adds AutoSSL excluded domains for a user.

B<Input>: domains is passed in as an array of 'domain'

    whmapi1 add_autossl_user_excluded_domains username=aardvark domain=ants.tld domain=tasty.tld

B<Output>:

    None.

=cut

sub add_autossl_user_excluded_domains {
    my ( $args, $metadata ) = @_;

    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );
    my $domains  = _get_domains_or_die($args);
    Cpanel::Validate::Username::user_exists_or_die($username);

    my $payload = _get_child_account_error_payload( $metadata, $username );
    return $payload if $payload;

    Cpanel::SSL::Auto::Exclude::Set::add_user_excluded_domains( 'user' => $username, 'domains' => $domains );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

=head2 B<remove_autossl_user_excluded_domains>

This function removes AutoSSL excluded domains for a user.

B<Input>: domains is passed in as an array of 'domain'

    whmapi1 remove_autossl_user_excluded_domains username=aardvark domain=ants.tld domain=tasty.tld

B<Output>:

    None.

=cut

sub remove_autossl_user_excluded_domains {
    my ( $args, $metadata ) = @_;

    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );
    my $domains  = _get_domains_or_die($args);
    Cpanel::Validate::Username::user_exists_or_die($username);

    my $payload = _get_child_account_error_payload( $metadata, $username );
    return $payload if $payload;

    Cpanel::SSL::Auto::Exclude::Set::remove_user_excluded_domains( 'user' => $username, 'domains' => $domains );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

=head2 get_autossl_problems_for_user

Returns the list of the last DCV problems a cPanel user's
account experienced

=head3 Input

=over 3

=item $user

    The cPanel User

=back

=head3 Output

=over 3

=item C<ARRAYREF> of C<HASHREF>s under the 'status_by_domain' keys

 {
    'problems_by_domain'
    =>
    [
        {
            domain => 'www.suba.bob1.org'
            problem => '“www.suba.bob1.org” does not resolve to any IPv4 addresses on the internet.',
            time => '2017-08-19T13:41:04Z',
        }
        ...
    ]
 }

=back

=cut

sub get_autossl_problems_for_user {
    my ( $args, $metadata ) = @_;

    my $user = Whostmgr::API::1::Utils::get_required_argument( $args, 'username' );
    Cpanel::Validate::Username::user_exists_or_die($user);

    my $payload = _get_child_account_error_payload( $metadata, $user );
    return $payload if $payload;

    require Cpanel::SSL::Auto::Problems;

    my $probs_ar = Cpanel::SSL::Auto::Problems->new()->get_for_user($user);

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'problems_by_domain' => $probs_ar };

}

=head2 get_autossl_problems_for_domain

Returns the list of the last DCV problems a cPanel user's
account experienced for a given domain

=head3 Input

=over 3

=item $domain

    The domain to get status for

=back

=head3 Output

=over 3

=item C<ARRAYREF> of C<HASHREF>s under the 'status_by_domain' keys

 {
    'problems_by_domain'
    =>
    [
        {
            domain => 'www.suba.bob1.org'
            problem => '“www.suba.bob1.org” does not resolve to any IPv4 addresses on the internet.',
            time => '2017-08-19T13:41:04Z',
        }
    ]
 }

=back

=cut

sub get_autossl_problems_for_domain {
    my ( $args, $metadata ) = @_;

    my $domain = Whostmgr::API::1::Utils::get_required_argument( $args, 'domain' );

    my $user = Cpanel::Domain::Owner::get_owner_or_die($domain);

    Cpanel::Validate::Username::user_exists_or_die($user);

    my $payload = _get_child_account_error_payload( $metadata, $user );
    return $payload if $payload;

    require Cpanel::SSL::Auto::Problems;

    my $probs_ar = Cpanel::SSL::Auto::Problems->new()->get_for_user($user);

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'problems_by_domain' => [ grep { $_->{domain} eq $domain } @$probs_ar ] };
}

sub _get_domains_or_die {
    my ($args) = @_;
    my $domains = _parse_domains($args);
    if ( not scalar @{$domains} ) {
        require Cpanel::Locale;
        die Cpanel::Locale->get_handle()->maketext('No domains specified.');
    }
    return $domains;
}

sub _parse_domains {
    my $args    = shift;
    my @domains = map { $args->{$_} } grep { $_ =~ /^domain(?:\-\d+)?$/ } ( keys %{$args} );
    return \@domains;
}

sub _do_hook {
    my ( $args, $event, $stage ) = @_;

    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => $event,
            'stage'    => $stage,
        },
        $args,
    );

    return 1;
}

1;
