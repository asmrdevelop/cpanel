package Cpanel::API::Sitejet;

# cpanel - Cpanel/API/Sitejet.pm                 Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::AdminBin::Call     ();
use Cpanel::Autodie            ();
use Cpanel::Exception          ();
use Cpanel::Locale             ();
use Cpanel::Logger             ();
use Cpanel::Server::Type       ();
use Cpanel::Sitejet::Connector ();

=encoding utf-8

=head1 NAME

Cpanel::API::Sitejet - wrapper to SiteJet api calls.

=head1 DESCRIPTION

A wrapper to call Sitejet REST API calls

=cut

my $non_mutating = { allow_demo => 1 };
my $mutating     = {};

our %API = (
    create_account                  => $non_mutating,
    get_templates                   => $non_mutating,
    set_template                    => $non_mutating,
    get_api_token                   => $non_mutating,
    add_api_token                   => $non_mutating,
    create_website                  => $non_mutating,
    publish                         => $non_mutating,
    get_user_site_metadata          => $non_mutating,
    get_all_sites_metadata          => $non_mutating,
    get_sso_link                    => $non_mutating,
    get_sitebuilder_domain_statuses => $non_mutating,
    disk_quota_check                => $non_mutating,
    get_all_user_sitejet_info       => $non_mutating,
    start_publish                   => $non_mutating,
    poll_publish                    => $non_mutating,
    create_restore_point            => $non_mutating,
    restore_document_root           => $non_mutating,
);

my $logger = Cpanel::Logger->new();
my $locale = Cpanel::Locale->get_handle();

=head2 create_account()

Create a sitejet account associated with the current logged in user.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/create_sitejet_account/> for more details.

=cut

sub create_account ( $args, $result ) {
    my $connector = Cpanel::Sitejet::Connector->new();
    my $res       = $connector->createAccount();
    Cpanel::AdminBin::Call::call( 'Cpanel', 'sitejet', 'ADD_API_TOKEN', $res->{key} );
    $result->data($res);

    return 1;
}

=head2 get_templates()

Get the list of templates available for Sitejet.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/get_sitejet_templates/> for more details.

=cut

sub get_templates ( $args, $result ) {
    my $connector = Cpanel::Sitejet::Connector->new();
    my $templates = $connector->cp_get_templates() or die Cpanel::Exception::create( 'InvalidParameter', 'Unable to access Sitejet templates. Try again later.' );
    $result->data($templates);

    return 1;
}

=head2 set_template(domain => ..., template_id => ...)

Set the Sitejet template for a given domain.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/set_sitejet_template/> for more details.

=cut

sub set_template ( $args, $result ) {
    my $domain       = $args->get_length_required('domain');
    my $templateId   = $args->get_length_required('templateId');
    my $templateName = $args->get_length_required('templateName');

    _validate_user_domain($domain);
    my $connector = Cpanel::Sitejet::Connector->new();

    my $res = $connector->selectTemplateForWebsite( $domain, $templateId, $templateName ) or die Cpanel::Exception::create( 'InvalidParameter', 'Unable to set Sitejet template for “[_1]”.', [$domain] );
    $result->data($res);

    return 1;
}

=head2 get_sso_link(domain => ..., referrer => ...)

Fetch the sso link for the specific domain.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/get_sitejet_sso_link/> for more details.

=cut

sub get_sso_link ( $args, $result ) {
    my $domain   = $args->get_length_required('domain');
    my $referrer = $args->get_length_required('referrer');
    require Cpanel::Locale::Utils::User;
    my $locale = Cpanel::Locale::Utils::User::get_user_locale($Cpanel::user);

    _validate_user_domain($domain);
    my $connector = Cpanel::Sitejet::Connector->new();

    require Cpanel::License::CompanyID;
    my $company_id = Cpanel::License::CompanyID::get_company_id();

    my %args = (
        'domain'     => $domain,
        'referrer'   => $referrer,
        'locale'     => $locale,
        'company_id' => $company_id
    );

    my $sso = $connector->getSSOLinkForWebsite( \%args ) or die Cpanel::Exception::create( 'InvalidParameter', 'Failed to get SSO link for domain: “[_1]”.', [$domain] );
    $result->data($sso);

    return 1;
}

=head2 get_preview_url(websiteId => ...)

Retrieve the website preview url for the website identified by C<websiteId>.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/get_sitejet_preview_url/> for more details.

=cut

sub get_preview_url ( $args, $result ) {
    my $websiteId = $args->get_length_required('websiteId');

    my $connector = Cpanel::Sitejet::Connector->new();
    my $url       = $connector->cp_getPreviewUrl($websiteId);
    $result->data($url);

    return 1;
}

=head2 get_api_token()

Get the Sitejet API access token for the current cPanel user.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/get_sitejet_api_token/> for more details.

=cut

sub get_api_token ( $args, $result ) {
    my $api_token = Cpanel::Sitejet::Connector::loadApiKey();
    $result->data($api_token);
    return 1;
}

=head2 add_api_token(api_token => ...)

Add a Sitejet api access token to the current cPanel user.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/add_sitejet_api_token/> for more details.

=cut

sub add_api_token ( $args, $result ) {
    my $api_token = $args->get_length_required('api_token');

    # XXX do we need to validate the api_token??
    Cpanel::AdminBin::Call::call( 'Cpanel', 'sitejet', 'ADD_API_TOKEN', $api_token );

    return 1;

}

=head2 create_website(...)

Create a website with Sitejet.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/create_sitejet_website/> for more details.

=cut

sub create_website ( $args, $result ) {
    my %website_info = (
        domain    => $args->get_length_required('domain'),
        company   => $args->get_length_required('company'),
        title     => $args->get('title'),
        firstname => $args->get('firstname'),
        lastname  => $args->get('lastname'),
        street    => $args->get('street'),
        zip       => $args->get('zip'),
        city      => $args->get('city'),
        country   => $args->get('country'),
        language  => $args->get('language'),
        email     => $args->get('email'),
        phone     => $args->get('phone'),
        note      => $args->get('note'),
        metadata  => $args->get('metadata'),
        assignTo  => $args->get('assignTo'),
        language  => $args->get('language') // 'en',

        # hardcoded as does Plesk
        fullcms => 1,

        cpanelDomainGUID => $args->get_length_required('domain'),
    );

    _validate_user_domain( $website_info{domain} );
    my $connector = Cpanel::Sitejet::Connector->new();

    my $website_id = $connector->createWebsite( \%website_info );
    $result->data($website_id);

    return 1;
}

=head2 get_user_site_metadata(domain => ...)

Fetch the metadata for the site hosted at the C<domain>

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/get_user_sitejet_site_metadata/> for more details.

=cut

sub get_user_site_metadata ( $args, $result ) {
    my $domain = $args->get_length_required('domain');

    _validate_user_domain($domain);
    my $connector = Cpanel::Sitejet::Connector->new();

    my $ret_hr = $connector->cp_load_sitejet_metadata($domain);
    $result->data($ret_hr);

    return 1;
}

=head2 get_all_sites_metadata(domain => ...)

Fetch the metadata for all the sites for the current cPanel user.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/get_all_sitejet_sites_metadata/> for more details.

=cut

sub get_all_sites_metadata ( $args, $result ) {
    my $connector = Cpanel::Sitejet::Connector->new();
    my $ret       = $connector->cp_load_all_sitejet_domains_metadata();
    $result->data($ret);

    return $ret;
}

=head2 publish(domain => ...)

Publish a site built with Sitejet to the docroot directory for the selected domain.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/publish_sitejet/> for more details.

=cut

sub publish ( $args, $result ) {
    my $domain = $args->get('domain');
    _validate_user_domain($domain);
    require DateTime;
    my $log_file = "$Cpanel::homedir/logs/publish_" . DateTime->now->datetime . ".log";
    my ( $log, $log_entry ) = _create_logging_stream_dir('sitejet');
    Cpanel::Autodie::symlink( $log_file, $log );

    require Cpanel::Daemonizer::Tiny;
    my $pid = Cpanel::Daemonizer::Tiny::run_as_daemon(
        sub {
            Cpanel::initcp($Cpanel::user);
            require Cpanel::Sitejet::Publish;
            eval { Cpanel::Sitejet::Publish::publish( $domain, $log_file ); };

            if ( my $exception = $@ ) {
                _log_exceptions( $log_file, $exception );
                local $Cpanel::Plugins::Log::_DIR = "$Cpanel::homedir/logs/sitejet";
                Cpanel::Plugins::Log::set_metadata( "${log_entry}", CHILD_ERROR => 1 );
            }
            else {
                local $Cpanel::Plugins::Log::_DIR = "$Cpanel::homedir/logs/sitejet";
                Cpanel::Plugins::Log::set_metadata( "${log_entry}", CHILD_ERROR => 0 );
            }
        }
    );

    $result->data( { 'pid' => $pid, 'log_entry' => $log_entry, 'user' => $Cpanel::user } );
    return 1;
}

=head2 start_publish(domain => ...)

Publish a site built with Sitejet to the docroot directory for the selected domain.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/start_publish_sitejet/> for more details.

=cut

sub start_publish ( $args, $result ) {
    my $domain        = $args->get_length_required('domain');
    my $clean_up_flag = $args->get('cleanup') || 0;
    if ($clean_up_flag) {
        require Cpanel::Sitejet::Publish;
        my $document_root = Cpanel::Sitejet::Publish::get_document_root($domain);
        my @dont_delete   = do_not_delete_list( $Cpanel::user, $document_root );
        _clean_up( $document_root, \@dont_delete );
    }

    _validate_user_domain($domain);
    require DateTime;
    require Cpanel::SafeDir::MK;

    # log is not generated if log_dir is not available
    my $log_dir = "$Cpanel::homedir/logs";
    Cpanel::SafeDir::MK::safemkdir_or_die( $log_dir, '0710' ) if !-d $log_dir;
    my $log_file = "$log_dir/publish_" . DateTime->now->datetime . ".log";

    require Cpanel::Daemonizer::Tiny;
    my $pid = Cpanel::Daemonizer::Tiny::run_as_daemon(
        sub {
            Cpanel::initcp($Cpanel::user);
            require Cpanel::Sitejet::Publish;
            require Cpanel::FileUtils::TouchFile;
            eval { Cpanel::Sitejet::Publish::publish( $domain, $log_file ); };

            if ( my $exception = $@ ) {
                Cpanel::FileUtils::TouchFile::touchfile("$log_file.failed");
                _log_exceptions( $log_file, $exception );
            }
        }
    );

    $result->data( { 'pid' => $pid, 'file_name' => $log_file } );
    return 1;
}

=head2 poll_publish(file_name => ...)

Read the publish log and return file contents.
Provide the publish pid status.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/poll_publish/> for more details.

=cut

sub poll_publish ( $args, $result ) {
    my $file_name = $args->get_length_required('file_name');
    my $pid       = $args->get_length_required('pid');
    my @file_content;
    my $completed_status = 0;

    Cpanel::Autodie::open( my $fh, '<', $file_name );

    while ( my $data = <$fh> ) {
        chomp($data);
        if ( $data =~ /Completed status: (\d+)%$/ ) {

            # highly unlikely it might go above 100
            # but just in case
            $completed_status = $1 > 100 ? 100 : $1;
        }
        push @file_content, $data;
    }
    close $fh;

    my $is_pid_alive = 0;
    my $failed       = 1;
    if ( !-e "$file_name.failed" ) {
        local $!;
        $is_pid_alive = kill 'ZERO', $pid;
        if ( !$is_pid_alive && $! && $! =~ /No such process/i ) {
            $failed = 0;
        }
        elsif ( !$is_pid_alive ) {

            $failed = $! ? 1 : 0;
        }
        else {
            $failed = 0;
        }
    }
    $result->data( { 'is_running' => $is_pid_alive, 'failed' => $failed, 'log' => \@file_content, 'progress' => $completed_status } );

    return 1;
}

sub _validate_user_domain ($domain) {
    require Cpanel::DomainLookup::DocRoot;
    my @user_domains = keys %{ Cpanel::DomainLookup::DocRoot::getdocroots($Cpanel::user) };

    if ( !grep { /^\Q$domain\E$/ } @user_domains ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” domain is not owned by this account.', [$domain] );
    }

    return 1;
}

sub _create_logging_stream_dir ($name) {
    require Cpanel::ProcessLog::WithChildError;
    require Cpanel::Plugins::Log;

    # overriding the default plugins log directory
    local $Cpanel::Plugins::Log::_DIR = "$Cpanel::homedir/logs/sitejet";
    my $log_entry = Cpanel::Plugins::Log::create_new( $name, 'CHILD_ERROR' => '?' );
    my $log       = "$Cpanel::Plugins::Log::_DIR/$log_entry/txt";
    Cpanel::Autodie::unlink_if_exists($log);
    return ( $log, $log_entry );
}

=head2 get_sitebuilder_domain_statuses(domain => ...)

Publish a site built with Sitejet to the docroot directory for the selected domain.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/get_sitebuilder_domain_statuses/> for more details.

=cut

sub get_sitebuilder_domain_statuses ( $args, $result ) {
    my $domain = $args->get('domain');
    _validate_user_domain($domain) if $domain;
    my $connector = Cpanel::Sitejet::Connector->new();
    my $ret       = $connector->cp_list_all_domain_sitebuilders($domain);
    $result->data($ret);

    return $ret;
}

=head2 disk_quota_check()

This function checks if a user has sufficient free space to perform
the back up of the document_root.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/sitejet_disk_quota_check/> for more details.

=head3 ARGUMENTS

=over

=item domain - string
Optional. The name of the domain.
If no arguments are provided, it performs the check on all user owned domains.

=back

=head3 RETURNS

1 if there is free space available or if an user has `unlimited` quota.
0 if there is not enough free space available.

=cut

sub disk_quota_check ( $args, $result ) {
    my $domain = $args->get('domain');
    _validate_user_domain($domain) if $domain;
    require Cpanel::Sitejet::Publish;
    my $ret = Cpanel::AdminBin::Call::call( 'Cpanel', 'sitejet', 'DISK_QUOTA_CHECK', $domain );
    $result->data($ret);
    return $ret;
}

=head2 get_all_user_sitejet_info()

This function provides the consolidated view of all sitejet related
information for a single domain or all user owned domains. This includes
sitejet metadata, integration status with sitejet and disk quota check.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/get_all_user_sitejet_info/> for more details.

=head3 ARGUMENTS

=over

=item domain - string
Optional. The name of the domain.
If no arguments are provided, it performs the check on all user owned domains.

=back

=head3 RETURNS
    Reference to array of anonymous hashes containing information about
    each domain website or individual domain website which looks something like this:
    [
        {
            'metadata' => {
                'document_root'    => '/home/user/public_html',
                'company'          => 'userdomain.tld',
                'websiteId'        => 399661,
                'publish_status'   => 1,
                'templateId'       => '371888',
                'templateName'     => 'A great template' 'fullcms' => 1,
                'cpanelDomainGUID' => 'userdomain.tld',
                'language'         => 'en'
            },
            'status' => {
                'has_sitejet_published'  => 1,
                'is_sitejet'             => 1,
                'has_sitejet_website'    => 1,
                'has_sitejet_templateId' => 1
            },
            'quota' => {
                'required_space'   => 22,
                'can_backup'       => 1,
                'available_space'  => 281,
                'is_docroot_empty' => 0
            },
            'domain'                     => 'userdomain.tld',
            'redirection_enabled'        => 0,
            'shared_doc_root'            => 1,
            'is_restore_point_available' => 1,
        }
    ]

=cut

sub get_all_user_sitejet_info ( $args, $result ) {
    my $domain = $args->get('domain');
    _validate_user_domain($domain) if $domain;

    my ( $domains, $domain_shared_docroot_hr ) = _get_domains();
    my $connector = Cpanel::Sitejet::Connector->new();

    # fetch single domain info when requested
    @$domains = $domain if $domain;

    my @final_data = ();

    foreach my $domain ( sort @$domains ) {
        my %build_data;
        my $document_root;

        # TODO: DUCK-9753
        my $status_hr  = $connector->cp_list_all_domain_sitebuilders($domain);
        my $disk_quota = Cpanel::AdminBin::Call::call( 'Cpanel', 'sitejet', 'DISK_QUOTA_CHECK', $domain );
        $build_data{'domain'}              = $domain;
        $build_data{'shared_doc_root'}     = $domain_shared_docroot_hr->{$domain} // 0;
        $build_data{'redirection_enabled'} = _get_redirect_info($domain);
        $build_data{'status'}              = $status_hr->{$domain};

        $build_data{'metadata'} = _cleanse_data( $connector, $domain );

        $build_data{'quota'}                      = $disk_quota->{$domain};
        $build_data{'is_restore_point_available'} = _is_restore_point_available( $build_data{'metadata'} );

        push @final_data, \%build_data;
    }

    $result->data( \@final_data );

    return 1;

}

sub _cleanse_data ( $connector, $domain ) {
    my $metadata       = $connector->cp_load_sitejet_metadata($domain);
    my @keys_to_remove = ( 'zz_light_bg', 'zz_dark_bg', 'domain' );
    delete @$metadata{@keys_to_remove};

    if ( !exists( $metadata->{'document_root'} ) ) {
        require Cpanel::Sitejet::Publish;
        $metadata->{'document_root'} = Cpanel::Sitejet::Publish::get_document_root($domain);
    }
    return $metadata;
}

sub _get_redirect_info ($domain) {
    require Cpanel::API;
    my $api_result = Cpanel::API::execute_or_die( 'Mime', 'get_redirect', { 'domain' => $domain } );
    my $redirects  = $api_result->{data};
    my $target_url = $redirects->{url} // '';

    # do not consider any self redirects with www
    # domain.com redirected to www.domain.com should not
    # block sitejet site creation or display warning.
    if ( $redirects->{'redirection_enabled'} && $target_url =~ m{^https?://(www\.)?$domain/}n ) {
        return 0;
    }
    return $redirects->{'redirection_enabled'} // 0;

}

sub _get_domains() {
    my $domains_hr = Cpanel::Sitejet::Connector::execute_list_domains();
    my @domains;
    my $main_domain;

    foreach my $domain_type ( keys %{$domains_hr} ) {
        if ( $domain_type eq 'main_domain' ) {
            $main_domain = $domains_hr->{'main_domain'};
            push @domains, $main_domain;
            next;
        }
        push @domains, @{ $domains_hr->{$domain_type} };
    }
    my $shared_doc_root = _get_shared_doc_root( $main_domain, \@domains );
    return ( \@domains, $shared_doc_root );
}

sub _get_shared_doc_root ( $main_domain, $domains_ar ) {
    require Cpanel::DomainLookup::DocRoot;
    my %domains_docroots = %{ Cpanel::DomainLookup::DocRoot::getdocroots($Cpanel::user) };
    my %doc_root_count;
    my %shared_doc_root;
    foreach my $domain ( sort @$domains_ar ) {
        my $doc_root = $domains_docroots{$domain};
        $doc_root_count{$doc_root}++;

        next if $domain eq $main_domain;

        # if there are multiple sub-domains that share doc_root, allow
        # the first alphabetically sorted sub domain to have a sitejet site.
        if ( $domains_docroots{$main_domain} eq $doc_root || $doc_root_count{$doc_root} > 1 ) {
            $shared_doc_root{$domain} = 1;
        }
    }
    return \%shared_doc_root;
}

sub _log_exceptions ( $log_file, $exception ) {
    open my $append_fh, '>>', "$log_file" or Cpanel::Exception::create( "IO::FileWriteError", [ path => $log_file, error => $! ] );
    print $append_fh "The publication process failed due to following exception: $exception";
    close $append_fh;
}

=head2 create_restore_point(domain => ...)

Create a restoration point for the document root
by compressing it as .gz file.

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/create_restore_point/> for more details.

=cut

sub create_restore_point ( $args, $result ) {
    my $domain = $args->get_length_required('domain');
    _validate_user_domain($domain);
    require Cpanel::Sitejet::Publish;
    my $document_root    = Cpanel::Sitejet::Publish::get_document_root($domain);
    my $homedir          = $Cpanel::homedir;
    my ($target_folder)  = $document_root =~ m{([^/]+)$};
    my $file_name        = $domain . '_' . time . '.gz';
    my $target_file_name = "$homedir/$file_name";

    my @dont_delete       = do_not_delete_list( $Cpanel::user, $document_root );
    my @exclude_statement = map { "--exclude=$_" } @dont_delete;

    # create .gz backup file in user home dir
    require Cpanel::SafeRun::Errors;
    require Cpanel::Tar;
    require Cpanel::SafeRun::Object;

    my $run = Cpanel::SafeRun::Object->new( 'program' => Cpanel::Tar::load_tarcfg()->{'bin'}, 'args' => [ @exclude_statement, '-c', '-v', '-z', '-f', $target_file_name, $document_root ] );

    if ( $run->CHILD_ERROR() ) {
        my $error = $run->stderr();
        if ( $error =~ /Disk quota exceeded/ ) {
            $result->error( $locale->maketext("The system cannot create a restore point because your account has exceeded quota limits.") );

        }
        else {
            $result->error( $locale->maketext("The system failed to create a restore point.") );
        }
        $logger->warn("The create_restore_point failed due to the following error: $error");

        # in case of failure, remove the zip file if it exists.
        eval { Cpanel::Autodie::unlink_if_exists($target_file_name) if -e $target_file_name; };
        $logger->warn("Unable to remove restore_file '$target_file_name' when create_restore_point failed.") if $@;

        return 0;
    }

    # update metadata
    _update_metadata( $domain, $target_file_name );

    # clean-up on successful backup
    _clean_up( $document_root, \@dont_delete );

    return 1;
}

=head2 restore_document_root(domain => ...)

Restore the document_root from the restore_file

See L<https://api.docs.cpanel.net/openapi/cpanel/operation/restore_document_root/> for more details.

=cut

sub restore_document_root ( $args, $result ) {
    my $domain = $args->get_length_required('domain');
    _validate_user_domain($domain) if $domain;
    my $connector        = Cpanel::Sitejet::Connector->new();
    my $sitejet_metadata = $connector->cp_load_sitejet_metadata($domain);
    my $restore_file     = $sitejet_metadata->{'restore_file'} if exists $sitejet_metadata->{'restore_file'};
    if (   !$restore_file
        || !-f $restore_file ) {
        $result->error( $locale->maketext( "The system cannot restore your files from the restore point because the restore point file “[_1]” is missing.", $restore_file ) );
        return 0;
    }

    # since we have a restore_file,
    # we can start deleting sitejet files.
    my $sitejet_file_tracking = "$connector->{'config_dir'}/$domain-files";
    if ( !-f $sitejet_file_tracking ) {
        $result->error( $locale->maketext( "The system cannot restore your files because the SiteJet tracking file “[_1]” is missing.", $sitejet_file_tracking ) );
        return 0;
    }
    _remove_sitejet_files( $sitejet_file_tracking, $domain );
    require Cpanel::Tar;
    require Cpanel::SafeRun::Object;

    my $run = Cpanel::SafeRun::Object->new( 'program' => Cpanel::Tar::load_tarcfg()->{'bin'}, 'args' => [ '-x', '-v', '-f', $restore_file, '-C', '/' ] );

    if ( $run->CHILD_ERROR() ) {
        my $error = $run->stderr();
        if ( $error =~ /Disk quota exceeded/ ) {
            $result->error( $locale->maketext("The system cannot restore your files from the restore point because your account has exceeded quota limits.") );
        }
        elsif ( $error =~ /No such file or directory/ ) {
            $result->error( $locale->maketext( "The system cannot restore your files from the restore point because the restore point file “[_1]” is missing.", $restore_file ) );
        }
        else {
            $result->error( $locale->maketext("The system cannot restore your files from the restore point.") );
        }
        $logger->warn("The restore_document_root failed due to the following error: $error");

        return 0;
    }

    # remove restore_file on successful restore
    eval { Cpanel::Autodie::unlink_if_exists($restore_file); };
    $logger->warn("The system unable to remove the restore file: '$restore_file' after successful restoration.") if $@;

    $connector->cp_update_sitejet_metadata( $domain, { 'restored_from_file' => $restore_file, 'restore_file' => '', 'latest_restore_date' => time } );
    return 1;

}

sub _update_metadata ( $domain, $restore_file ) {
    my $conn_obj    = Cpanel::Sitejet::Connector->new();
    my $config_file = $conn_obj->{config_dir} . '/' . $domain;
    my $data        = { 'restore_file' => $restore_file };
    $conn_obj->cp_update_sitejet_metadata( $domain, $data );

    return;
}

sub _remove_sitejet_files ( $sitejet_file_tracking, $domain ) {
    require Cpanel::Sitejet::Publish;
    my $document_root = Cpanel::Sitejet::Publish::get_document_root($domain);
    my @files_to_delete;
    my @dont_delete = do_not_delete_list( $Cpanel::user, $document_root );
    Cpanel::Autodie::open( my $fh, '<', $sitejet_file_tracking );
    while ( my $file = <$fh> ) {
        chomp($file);
        next if -d $file;
        my ($immediate_directory) = $file =~ m{$document_root/([^/\n]+)};

        # skip any nested subdirectories and non doc_root directories
        if ( !$immediate_directory || grep { $_ eq $immediate_directory } @dont_delete ) {
            next;
        }
        push @files_to_delete, $file;
    }

    close $fh;
    foreach my $file (@files_to_delete) {
        eval { Cpanel::Autodie::unlink_if_exists($file); };
        $logger->warn("The system unable to remove the sitejet file during restore process: '$file' ") if $@;
    }

    require Cpanel::Sitejet::Publish;
    Cpanel::Sitejet::Publish::cp_remove_unused_directories( $domain, @files_to_delete );
    return;

}

sub _is_restore_point_available ($sitejet_metadata) {
    if (   !exists $sitejet_metadata->{'restore_file'}
        || !$sitejet_metadata->{'restore_file'}
        || !-f $sitejet_metadata->{'restore_file'} ) {
        return 0;
    }
    return 1;
}

sub do_not_delete_list ( $user, $document_root ) {

    require Cpanel::PwCache;
    my $homedir = $Cpanel::homedir || Cpanel::PwCache::gethomedir($user);

    # get the first immediate folder name after doc root
    require Cpanel::DomainLookup;
    require Cpanel::WebDisk;
    my @sub_docroots = map { m<$document_root/([^/\n]+)>; } keys %{ Cpanel::DomainLookup::getdocrootlist($user) };

    my @webdisks = Cpanel::WebDisk::api2_listwebdisks( home_dir => $homedir, );

    my @webdiskusers_docroots = map {
        $_->{homedir} =~ m<^$document_root/([^/]+)>;    # this one gives $1
    } @webdisks;
    my @dont_delete = (
        '.htaccess',
        '.well-known',
        '400.shtml',
        '401.shtml',
        '403.shtml',
        '404.shtml',
        '413.shtml',
        '500.shtml',
        'cp_errordocument.shtml',
        @sub_docroots,
        @webdiskusers_docroots,
    );
    return @dont_delete;
}

sub _clean_up ( $document_root, $dont_delete_ar ) {
    Cpanel::Autodie::opendir( my $dh, $document_root );

    # collect files to delete
    my @contents = grep { !/^\.\.?$/ } readdir($dh);

    # delete the files/dirs
    require Cpanel::SafeDir::RM;

    foreach my $content (@contents) {

        # exclude any immediate folders for webdisk & sub_docroots
        next if grep { $_ eq $content } @$dont_delete_ar;
        my $file = "$document_root/$content";
        eval { -d $file ? Cpanel::SafeDir::RM::safermdir($file) : Cpanel::Autodie::unlink_if_exists($file); };
        $logger->warn("Unable to clean up file '$file'. Skipping this and moving on...") if $@;
    }
    return;
}

1;
