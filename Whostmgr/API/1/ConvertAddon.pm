package Whostmgr::API::1::ConvertAddon;

# cpanel - Whostmgr/API/1/ConvertAddon.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;
use Cpanel::Imports;

use Whostmgr::ACLS                           ();
use Cpanel::Apache::TLS                      ();
use Cpanel::Exception                        ();
use Cpanel::LoadModule                       ();
use Whostmgr::API::1::Utils                  ();
use Whostmgr::Transfers::ConvertAddon::Utils ();

use constant NEEDS_ROLE => 'WebServer';

my $CONVERT_SCRIPT = '/usr/local/cpanel/bin/convert_addon_to_account';

sub convert_addon_list_addon_domains {
    my ( undef, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    my $domain_data = {};
    try {
        $domain_data = Whostmgr::Transfers::ConvertAddon::Utils::get_domain_data( { 'hasroot' => scalar Whostmgr::ACLS::hasroot(), 'user' => $ENV{'REMOTE_USER'}, 'only_addons' => 1 } );
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'The system failed to fetch the list of addon domains: [_1]', Cpanel::Exception::get_string( $_, 'no_id' ) );
    };
    return if not $metadata->{'result'};

    return $domain_data;
}

# stubbed in tests
sub _forbid_distributed_account ($domain) {
    require Cpanel::Domain::Owner;
    my $username = Cpanel::Domain::Owner::get_owner_or_die($domain);

    require Cpanel::Config::LoadCpUserFile;
    my $cpuser_obj = Cpanel::Config::LoadCpUserFile::load_or_die($username);

    my $is_distributed = $cpuser_obj->child_workloads();

    $is_distributed ||= do {
        require Cpanel::LinkedNode::Worker::GetAll;
        Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser($cpuser_obj);
    };

    if ($is_distributed) {
        die locale()->maketext( "The distributed account “[_1][comment,username]” owns that addon domain. First use [asis,WHM]’s “[_2]” interface to dedistribute the account. Then, you can convert the addon domain to a [asis,cPanel] account.", $username, locale()->maketext('Modify an Account') ) . $/;
    }

    return;
}

sub convert_addon_initiate_conversion {
    my ( $args, $metadata ) = @_;    # $args are not filtered by xml-api

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    try {

        # Don’t bother checking for distributed account if no
        # domain was given because we’ll catch that below.
        _forbid_distributed_account( $args->{'domain'} ) if $args->{'domain'};

        my $sanitized_args_hr = _parse_initiation_args($args);
        if ( $ENV{'REMOTE_USER'} ) {
            $sanitized_args_hr->{'notify-user'} //= $ENV{'REMOTE_USER'};
        }

        my @script_args = map { '--' . $_, $sanitized_args_hr->{$_} } ( grep { $_ !~ m/^(copy-mysqldb|move-mysqldb|move-mysqluser)$/ } keys %{$sanitized_args_hr} );
        if ( $sanitized_args_hr->{'copy-mysqldb'} && scalar @{ $sanitized_args_hr->{'copy-mysqldb'} } % 2 == 0 ) {
            while ( @{ $sanitized_args_hr->{'copy-mysqldb'} } ) {

                # use of List::MoreUtils::natatime is currently not allowed by our coding standard...
                # so this is another way of doing that
                push @script_args, '--copy-mysqldb', splice @{ $sanitized_args_hr->{'copy-mysqldb'} }, 0, 2;
            }
        }
        foreach my $db ( @{ $sanitized_args_hr->{'move-mysqldb'} } ) {
            push @script_args, '--move-mysqldb', $db;
        }
        foreach my $dbuser ( @{ $sanitized_args_hr->{'move-mysqluser'} } ) {
            push @script_args, '--move-mysqluser', $dbuser;
        }

        _start_conversion(@script_args);
    }
    catch {
        my $exceptions = ref $_ eq 'Cpanel::Exception::Collection' ? $_->get('exceptions') : [$_];

        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'The system failed to initiate the conversion process: [quant,_1,error,errors] occurred', scalar @{$exceptions} );
        $metadata->{'errors'} = [ map { Cpanel::Exception::get_string( $_, 'no_id' ) } @{$exceptions} ];
    };
    return if not $metadata->{'result'};

    return {};
}

sub convert_addon_fetch_domain_details {
    my ( $args, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    my $domain_details;
    try {
        my $domain = $args->{'domain'};
        die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['domain'] )
          if !$domain;

        my $basic_details = Whostmgr::Transfers::ConvertAddon::Utils::get_addon_domain_details( $args->{'domain'} );
        die Cpanel::Exception::create( 'DomainDoesNotExist', 'The addon domain “[_1]” does not exist.', [ $args->{'domain'} ] )
          if !$basic_details;

        @{$domain_details}{qw(docroot owner ip has_dedicated_ip)} = @{$basic_details}{qw(docroot owner ip has_dedicated_ip)};
        $domain_details->{'number_of_email_accounts'}    = Whostmgr::Transfers::ConvertAddon::Utils::get_email_account_count_for_domain( $domain_details->{'owner'}, $domain );
        $domain_details->{'number_of_email_forwarders'}  = Whostmgr::Transfers::ConvertAddon::Utils::get_email_forwarder_count_for_domain( $domain_details->{'owner'}, $domain );
        $domain_details->{'number_of_domain_forwarders'} = Whostmgr::Transfers::ConvertAddon::Utils::get_domain_forwarder_count_for_domain($domain);
        $domain_details->{'number_of_autoresponders'}    = Whostmgr::Transfers::ConvertAddon::Utils::get_autoresponder_count_for_domain( $domain_details->{'owner'}, $domain );
        $domain_details->{'is_sni_supported'}            = 1;

        my $apache_vhost_name = Whostmgr::Transfers::ConvertAddon::Utils::get_addon_domain_details($domain)->{'subdomain'};
        $domain_details->{'has_ssl_cert_installed'} = Cpanel::Apache::TLS->has_tls($apache_vhost_name);
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'The system failed to fetch domain details: [_1]', Cpanel::Exception::get_string( $_, 'no_id' ) );
    };
    return if not $metadata->{'result'};

    return $domain_details;
}

sub convert_addon_list_conversions {
    my ( undef, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    my $conversion_list;
    try {
        Cpanel::LoadModule::load_perl_module('Whostmgr::AcctInfo::Owner');
        Cpanel::LoadModule::load_perl_module('Cpanel::ProgressTracker::ConvertAddon::DB');
        my $db = Cpanel::ProgressTracker::ConvertAddon::DB->new( { 'read_only' => 1 } );
        $conversion_list = [ grep { $ENV{'REMOTE_USER'} eq $_->{'source_acct'} || Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $_->{'source_acct'} ) } @{ $db->list_jobs() } ];
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'The system failed to fetch the list of conversions: [_1]', Cpanel::Exception::get_string_no_id($_) );
    };
    return if not $metadata->{'result'};

    return { 'conversions' => $conversion_list };
}

sub convert_addon_fetch_conversion_details {
    my ( $args, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    my $job_details;
    try {
        my $job_id = $args->{'job_id'};
        die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['job_id'] )
          if !$job_id;

        Cpanel::LoadModule::load_perl_module('Whostmgr::AcctInfo::Owner');
        Cpanel::LoadModule::load_perl_module('Cpanel::ProgressTracker::ConvertAddon::DB');
        my $db = Cpanel::ProgressTracker::ConvertAddon::DB->new( { 'read_only' => 1 } );

        # Returns a hashref if the job_id was in the DB.
        # undef otherwise.
        $job_details = $db->fetch_job_details($job_id);
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid “[_2]”.', [ $job_id, 'job_id' ] )
          if !( $job_details && ( $ENV{'REMOTE_USER'} eq $job_details->{'source_acct'} || Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $job_details->{'source_acct'} ) ) );
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'The system failed to fetch the conversion job details: [_1]', Cpanel::Exception::get_string_no_id($_) );
    };
    return if not $metadata->{'result'};

    return $job_details;
}

sub convert_addon_get_conversion_status {
    my ( $args, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    my $conversion_status;
    try {
        my $job_ids = _parse_job_ids($args);

        die Cpanel::Exception::create( 'MissingParameter', 'You must specify at least one valid “[_1]”.', ['job_id'] )
          if !scalar @{$job_ids};

        Cpanel::LoadModule::load_perl_module('Whostmgr::AcctInfo::Owner');
        Cpanel::LoadModule::load_perl_module('Cpanel::ProgressTracker::ConvertAddon::DB');
        my $db = Cpanel::ProgressTracker::ConvertAddon::DB->new( { 'read_only' => 1 } );

        # Returns a hashref if the job_id(s) are in the DB.
        # undef otherwise.
        $conversion_status = $db->get_job_status( @{$job_ids} );
        $conversion_status = {
            map  { $_ => $conversion_status->{$_} }
            grep { $ENV{'REMOTE_USER'} eq $conversion_status->{$_}->{'source_acct'} || Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $conversion_status->{$_}->{'source_acct'} ) } ( keys %{$conversion_status} )
        };

        die Cpanel::Exception::create( 'InvalidParameter', 'You must specify at least one valid “[_1]”.', ['job_id'] )
          if !scalar keys %{$conversion_status};
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = locale->maketext( 'The system failed to fetch the conversion job status: [_1]', Cpanel::Exception::get_string_no_id($_) );
    };
    return if not $metadata->{'result'};

    return $conversion_status;
}

sub _parse_job_ids {
    my $args    = shift;
    my @job_ids = map { $args->{$_} } grep { $_ =~ /^job_id(\-\d+)?$/ } ( keys %{$args} );
    return \@job_ids;
}

sub _parse_initiation_args {
    my $args = shift;

    Cpanel::LoadModule::load_perl_module('Whostmgr::Transfers::ConvertAddon::Utils::Params');

    # Accommodate calls that use 'user' instead of 'username'
    # Accommodate calls that use 'email' instead of 'email-address'
    $args->{'username'}      //= delete $args->{'user'};
    $args->{'email-address'} //= delete $args->{'email'};

    $args->{'pkgname'} ||= 'default' if Whostmgr::ACLS::hasroot();

    my $exceptions_ar = _validate_parse_args($args);
    die Cpanel::Exception::create( 'Collection', [ exceptions => $exceptions_ar ] ) if scalar @{$exceptions_ar};

    # Parse the optional params, and populate the 'sanitized_args' hashref with
    # appropriately named keys so that they can be used to invoke the $CONVERT_SCRIPT properly.
    my $sanitized_args_hr = {
        ( map { $_        => $args->{$_} } Whostmgr::Transfers::ConvertAddon::Utils::Params::required_value_params() ),
        ( map { 'no' . $_ => '' } grep { defined $args->{$_}          && !$args->{$_} } Whostmgr::Transfers::ConvertAddon::Utils::Params::optional_flag_params() ),
        ( map { $_        => $args->{$_} } grep { defined $args->{$_} && ( ref $args->{$_} || length $args->{$_} ) } Whostmgr::Transfers::ConvertAddon::Utils::Params::optional_value_params() ),
    };

    return $sanitized_args_hr;
}

sub _validate_parse_args {
    my $args = shift;

    my $exceptions_ar;

    my $errors = Whostmgr::Transfers::ConvertAddon::Utils::Params::validate_required_params($args);
    push @{$exceptions_ar}, @{$errors};
    return $exceptions_ar if scalar @{$exceptions_ar};

    my $domain_details = Whostmgr::Transfers::ConvertAddon::Utils::get_addon_domain_details( $args->{'domain'} );
    my $migrate_opts   = {
        'from_username' => $domain_details->{'owner'},
        'to_username'   => $args->{'username'}
    };

    delete $args->{'copy-mysqldb'};
    delete $args->{'move-mysqldb'};
    delete $args->{'move-mysqluser'};
    foreach my $db_arg ( keys %{$args} ) {
        if ( $db_arg =~ m/^copymysqldb-(.+)$/ ) {
            my $new_name = delete $args->{$db_arg};
            push @{ $args->{'copy-mysqldb'} }, $1, $new_name;
        }
        elsif ( $db_arg =~ m/^movemysqldb(?:-[0-9]+)?$/ ) {
            my $dbname = delete $args->{$db_arg};
            push @{ $args->{'move-mysqldb'} }, $dbname;
        }
        elsif ( $db_arg =~ m/^movemysqluser(?:-[0-9]+)?$/ ) {
            my $dbuser = delete $args->{$db_arg};
            push @{ $args->{'move-mysqluser'} }, $dbuser;
        }
    }

    $errors = Whostmgr::Transfers::ConvertAddon::Utils::Params::validate_optional_value_params( $args, $migrate_opts );
    push @{$exceptions_ar}, @{$errors};

    return $exceptions_ar;
}

sub _start_conversion {
    my @script_args = @_;

    my $exit = system $CONVERT_SCRIPT, '--daemonize', @script_args;
    die Cpanel::Exception->create( 'The system failed to execute the conversion script: [_1]', [$CONVERT_SCRIPT] ) if $exit != 0;
    return;
}

1;
