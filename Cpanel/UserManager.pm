
# cpanel - Cpanel/UserManager.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::UserManager;

use strict;
use warnings;

use Cpanel::AcctUtils::DomainOwner    ();
use Cpanel::AdminBin::Call            ();
use Cpanel::AdminBin::Serializer      ();
use Cpanel::App                       ();
use Cpanel::Config::LoadCpConf        ();
use Cpanel::FileUtils::Write          ();
use Cpanel::FtpUtils::Server          ();
use Cpanel::IP::Remote                ();
use Cpanel::Debug                     ();
use Cpanel::PwCache                   ();
use Cpanel::PwCache::PwFile           ();
use Cpanel::Quota::Test               ();
use Cpanel::Rand::Get                 ();
use Cpanel::UserManager::Record       ();    # also used when upgrading the object via upgrade_obj
use Cpanel::UserManager::Record::Lite ();
use Cpanel::UserManager::Services     ();
use Cpanel::UserManager::Storage      ();
use Cpanel::Validate::VirtualUsername ();

use Cpanel::Locale::Lazy 'lh';

our $use_cache = 0;

my $percent_warn = 0.8;                      # Warn when 20% left.

sub MAX_SESSION_AGE {
    return 86400 * 2;                        # 2 days
}

sub list_users {
    my %args = @_;

    if ( $args{obj_transform} ) {
        return _list_users_no_cache(%args);    # bypass cache if we want anything other than the default representation
    }

    my $started_at = time();

    my $response;

    my $cache_key = join ':', map { join '=', $_ || '', $args{$_} || '' } sort keys %args;
    my $homedir   = Cpanel::PwCache::gethomedir();

    my $cache_dir = "$homedir/.cpanel/caches/user_manager";
    if ( !-d $cache_dir ) {
        mkdir $cache_dir;
    }
    my $cache_file = "$cache_dir/list_users:$cache_key";

    if ( $use_cache && -f $cache_file ) {
        my $cache_mtime = ( stat $cache_file )[9];
        if ( _account_storage_modified_since($cache_mtime) ) {
            unlink $cache_file;
        }
        else {
            $response = eval {
                local $SIG{'__DIE__'};
                local $SIG{'__WARN__'};
                Cpanel::AdminBin::Serializer::LoadFile($cache_file);
            };
            if ($@) {
                Cpanel::Debug::log_warn("Deleting corrupt cache file $cache_file");
                unlink $cache_file;
            }
        }
    }

    if ( !$response ) {
        $response = _list_users_no_cache(%args);

        if ($use_cache) {
            Cpanel::FileUtils::Write::overwrite(
                $cache_file,
                Cpanel::AdminBin::Serializer::Dump($response),
                0600
            );

            # Force the cache to have a timestamp at least 1 second before we started
            # gathering data. That way, even if some data changed while we were in the
            # middle of gathering it and so we missed it, it will still be guaranteed
            # to be picked up the next time the function is called.
            utime $started_at - 1, $started_at - 1, $cache_file;
        }
    }

    return $response;
}

sub _account_storage_modified_since {
    my ($cache_mtime) = @_;
    my $homedir       = $Cpanel::homedir || Cpanel::PwCache::gethomedir();
    my $user          = $Cpanel::user    || Cpanel::PwCache::getusername();

    my @files_to_invalidate_cache = (
        $homedir . '/.subaccounts/storage.sqlite',
        $homedir . '/.cpanel/email_accounts.json',
        '/etc/proftpd/' . $user,
        $homedir . '/etc/webdav/passwd',
        $homedir . '/etc/webdav/shadow'
    );

    for my $f (@files_to_invalidate_cache) {
        my $f_mtime = ( stat $f )[9] || 0;
        if ( $f_mtime > $cache_mtime ) {
            return 1;
        }
    }

    return 0;
}

sub _list_users_no_cache {
    my %args              = @_;
    my $arg_flat          = $args{flat};
    my $arg_guid          = $args{guid};
    my $arg_obj_transform = $args{obj_transform} || 'as_hashref';

    my %subaccounts_by_full_username;
    my %service_accounts_by_full_username;

    #########################################################################
    ## Gather accounts from the unified account storage.
    #########################################################################

    my $unified_accounts = Cpanel::UserManager::Storage::list_users( objtype => 'Cpanel::UserManager::Record::Lite', $arg_guid ? ( guid => $arg_guid ) : () );

    if ( 'ARRAY' eq ref $unified_accounts ) {
        foreach my $record_obj (@$unified_accounts) {
            my $full_username = $record_obj->full_username;
            if ( 'sub' eq $record_obj->type ) {
                $record_obj->can_set_password(1);
                $subaccounts_by_full_username{$full_username} = $record_obj;
            }
            else {
                die lh()->maketext( 'The system found the unexpected account type “[_1]” in the unified account storage.', $record_obj->type );
            }
        }
    }

    #########################################################################
    ## Gather service account annotations.
    ##
    ## These are ancillary data that tie service account ownership to
    ## a specific sub-account.
    #########################################################################

    my $annotation_list = Cpanel::UserManager::Storage::list_annotations();

    #########################################################################
    ## Gather the service accounts themselves.
    #########################################################################

    gather_email_accounts( \%service_accounts_by_full_username, { constructor_args => [ annotation_list => $annotation_list ] } );

    gather_ftp_accounts( \%service_accounts_by_full_username, { constructor_args => [ annotation_list => $annotation_list ] } );

    gather_webdisk_accounts( \%service_accounts_by_full_username, { constructor_args => [ annotation_list => $annotation_list ] } );

    #########################################################################
    ## Build response list based on gathered service accounts.
    #########################################################################

    my @response;

    my $all_merged_service_accounts = [];
    for my $accounts ( values %service_accounts_by_full_username ) {
        next if !@$accounts;
        my $full_username = $accounts->[0]->full_username();

        my $dismissed_service_accounts;
        my $merged_service_accounts;

        ( $dismissed_service_accounts, $merged_service_accounts, $accounts ) = _separate_service_accounts($accounts);

        # Add the needed data to handle conflict identification
        for my $account (@$dismissed_service_accounts) {
            $account->sub_account_exists( exists( $subaccounts_by_full_username{$full_username} )      ? 1 : 0 );
            $account->has_siblings( scalar @{ $service_accounts_by_full_username{$full_username} } > 1 ? 1 : 0 );
        }
        push @$all_merged_service_accounts, @$merged_service_accounts;
        push @response,                     map { $_->$arg_obj_transform } @$dismissed_service_accounts;

        next if !$accounts->[0];

        if (
            $arg_flat                                                                    # if the caller requested a flat response
            or ( @$accounts == 1 and !$subaccounts_by_full_username{$full_username} )    # or there is only one service account, and no such sub-account already exists
            or grep { $_->{special} } @$accounts                                         # or it's a special service account,
        ) {
            for my $account (@$accounts) {
                $account->sub_account_exists( exists( $subaccounts_by_full_username{$full_username} )      ? 1 : 0 );
                $account->has_siblings( scalar @{ $service_accounts_by_full_username{$full_username} } > 1 ? 1 : 0 );
            }
            push @response, map { $_->$arg_obj_transform } @$accounts;
        }
        elsif ( my $existing_subaccount = $subaccounts_by_full_username{$full_username} ) {

            # Add the needed data to handle conflict identification
            for my $account (@$accounts) {
                $account->parent_type('sub');
                $account->sub_account_exists(1);
            }
            $existing_subaccount->{merge_candidates} = [ map { $_->as_hashref } @$accounts ];
        }
        else {
            # Add the needed data to handle conflict identification
            for my $account (@$accounts) {
                $account->parent_type('hypothetical');
                $account->has_siblings( scalar @{ $service_accounts_by_full_username{$full_username} } > 1 ? 1 : 0 );
                $account->sub_account_exists(0);
            }
            my $hypothetical_account = Cpanel::UserManager::Record::Lite->new(
                {
                    type             => 'hypothetical',
                    username         => $accounts->[0]->username,
                    domain           => $accounts->[0]->domain,
                    merge_candidates => [ map { $_->as_hashref } @$accounts ],
                }
            );
            push @response, $hypothetical_account->$arg_obj_transform;
        }
    }

    for my $service_account (@$all_merged_service_accounts) {
        my $subaccount = $subaccounts_by_full_username{ $service_account->full_username } || next;

        $subaccount->absorb_service_account_attributes($service_account);
    }

    for my $account ( values %subaccounts_by_full_username ) {
        push @response, $account->$arg_obj_transform;
    }

    #########################################################################
    ## Add the cPanel account to this list as a fully formed user.
    #########################################################################

    my $cpanel_account = Cpanel::UserManager::Record::Lite->new(
        {
            type     => 'cpanel',
            username => $Cpanel::user,
            services => { email => { enabled => 1 }, ftp => { enabled => 1 }, webdisk => { enabled => 1 } },
            special  => 1,
        }
    );
    push @response, $cpanel_account->$arg_obj_transform;

    if ($arg_guid) {
        @response = grep { ( $_->{guid} || '' ) eq $arg_guid } @response;
    }

    return \@response;
}

sub create_user {
    my $args = shift;

    my @invite_attributes;
    if ( $args->{'send_invite'} ) {
        if (   !length $args->{'password'}
            && !length $args->{'password_hash'} ) {                      #they didn't provide a password, but it's okay.
            $args->{'password'} = Cpanel::Rand::Get::getranddata(20);    # Deliberate gibberish.
        }
        my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();
        if ( !$cpconf_ref->{'invite_sub'} ) {
            die lh->maketext( 'Subaccount invites are disabled on this server. To use this feature, you must enable WHM’s Tweak Setting “[_1]” option.', 'Account Invites for Subaccounts' );
        }

        @invite_attributes = (
            has_invite        => 1,
            invite_expiration => time() + MAX_SESSION_AGE(),
        );
    }
    my @mandatory_fields = qw/username domain/;
    push @mandatory_fields, $args->{password_hash} ? 'password_hash' : 'password';
    foreach my $field (@mandatory_fields) {
        if ( !length $args->{$field} ) {
            die lh->maketext( 'The system could not create the user. You must provide the following mandatory field: [_1]', $field );
        }
    }

    $args->{'username'} =~ tr{A-Z}{a-z};
    $args->{'domain'}   =~ tr{A-Z}{a-z};

    Cpanel::Validate::VirtualUsername::validate_for_creation_or_die( $args->{'username'} . '@' . $args->{'domain'} );

    my $cpuser = defined $args->{'team_owner'} ? $args->{'team_owner'} : $ENV{'USER'};
    if ( !Cpanel::AcctUtils::DomainOwner::is_domain_owned_by( $args->{'domain'}, $cpuser ) ) {
        die lh->maketext( 'You do not own the domain “[_1]”.', $args->{'domain'} );
    }

    Cpanel::Quota::Test::quotatest_or_die();

    my $created_user = Cpanel::UserManager::Storage::store(
        Cpanel::UserManager::Record->new(
            {
                synced_password => 1,    # because the services, if any, that we add below will have the same password as the sub-account itself. comes before args so we can override it.
                %$args,
                type             => 'sub',    # because this is a sub-account. comes after args so we can't override it.
                can_set_password => 1,        # because thats true for sub-accounts from the list api.
                @invite_attributes,
            }
        )
    );

    eval { Cpanel::UserManager::Services::setup_services_for($created_user) };
    if ( my $exception = $@ ) {
        Cpanel::UserManager::Storage::delete_user( $created_user->guid );
        die lh->maketext( 'The system failed to set up services for the user “[_1]” at the domain “[_2]”: [_3]', @$args{qw(username domain)}, $exception );
    }

    if ( $args->{'send_invite'} ) {
        eval {
            my $cookie = Cpanel::AdminBin::Call::call(
                'Cpanel',
                'user',
                'CREATE_INVITE',
                join( '@', @$args{qw(username domain)} ),
            );

            _send_email_notification( $created_user, $cookie );
        };

        if ( my $exception = $@ ) {
            die lh->maketext( 'The system created the “[_1]” user at the domain “[_2]”, but failed to send the invite because of the following error: [_3]', @$args{qw(username domain)}, $exception );
        }
    }

    # Do a full lookup so we get extended attributes
    return lookup_user( $created_user->guid );
}

sub delete_user {
    my %args              = @_;
    my $username          = $args{username};
    my $domain            = $args{domain};
    my $arg_obj_transform = $args{obj_transform} || 'as_hashref';
    my $record_obj        = Cpanel::UserManager::Storage::lookup_user( username => $username, domain => $domain );
    if ($record_obj) {
        Cpanel::UserManager::Storage::delete_user( $record_obj->guid );
        Cpanel::UserManager::Services::delete_services_for($record_obj);

        # We don't want any merge candidates from this user to disappear,
        # so let's gather them up, and send them back to the user for the
        # UI to do something with them.
        return _gather_service_accounts_for_user( $username, $domain, $arg_obj_transform );
    }

    die lh()->maketext( 'The system could not find the “[_1]” user at the “[_2]” domain.', $username, $domain );
}

sub edit_user {
    my ($new_attributes) = @_;

    my $send_invite     = delete $new_attributes->{send_invite};
    my $bare_record_obj = Cpanel::UserManager::Storage::lookup_user( username => $new_attributes->{username}, domain => $new_attributes->{domain} );
    my $record_obj      = $bare_record_obj ? lookup_user( $bare_record_obj->guid ) : undef;

    die lh()->maketext( 'The user “[_1]” at domain “[_2]” does not exist.', @$new_attributes{qw(username domain)} ) unless $record_obj;

    $record_obj->upgrade_obj;

    my $newobj = $record_obj->overlay($new_attributes);
    if ( $new_attributes->{password} ) {
        $newobj->password( $new_attributes->{password} );
        $newobj->synced_password(1);
        if ( $newobj->has_expired_invite() ) {
            $newobj->has_invite(0);

            # There's no need to set invite_expiration, since
            # has_expired_invite checks first to see if has_invite is
            # set. Setting it to nonsensical values will fail validation.
            # If an invite is reissued, invite_expiration gets set anyway!
        }
    }
    else {

        # Update the synced password flag in cases where we
        # are removing some of the services.
        my $services = 0;
        my $last_enabled_service;
        for my $service (qw(email ftp webdisk)) {
            if ( $newobj->services->{$service}{enabled} ) {
                $services++;
                $last_enabled_service = $service;
            }
        }

        if ( $services == 0 ) {

            # None left so they must be synced.
            $newobj->synced_password(1);
        }
        elsif ( $services == 1 and $last_enabled_service ) {

            if ( $record_obj->services->{$last_enabled_service}{enabled} ) {

                # If the remaining service is already enabled, check its password hash.
                # We only have one service, so if the service and subaccount passwords match,
                # then all passwords are synchronized.
                my $service_password_hash    = lookup_service_password_hash( $new_attributes->{username}, $new_attributes->{domain}, $last_enabled_service );
                my $subaccount_password_hash = $record_obj->password_hash;

                $newobj->synced_password(1) if $service_password_hash eq $subaccount_password_hash;
            }
            else {
                # On the other hand, if it wasn't already enabled, then we know for sure that the
                # passwords are going to be synced, because it will use the password hash from the
                # subaccount when creating the service account below (adjust_services_for).
                $newobj->synced_password(1);
            }
        }

        # otherwise, its left as it was.
    }

    if ( Cpanel::UserManager::Storage::amend($newobj) ) {
        Cpanel::UserManager::Services::adjust_services_for( $record_obj, $newobj );

        my $newobj_with_full_attributes = lookup_user( $newobj->guid );
        return $newobj_with_full_attributes;
    }
    return undef;
}

# Look up a user. This lookup provides a more complete response than the one you get back from
# Cpanel::UserManager::Storage::lookup_user because it also goes through the steps of looking
# up potentially related service accounts.
sub lookup_user {
    my $guid  = shift || die lh()->maketext('The system could not find the user’s unique [asis,ID] .') . "\n";
    my $found = list_users( guid => $guid, obj_transform => 'as_self' );
    if ( 'ARRAY' ne ref $found or !@$found ) {
        die lh()->maketext('The user does not exist.') . "\n";
    }
    elsif ( @$found > 1 ) {
        die lh()->maketext('An error occurred. The User Manager database contains multiple accounts with the same unique [asis,ID].') . "\n";
    }
    return $found->[0];
}

sub _gather_service_accounts_for_user {
    my ( $username, $domain, $arg_obj_transform ) = @_;
    my @accounts;
    my %service_accounts;
    my $full_username = $username . '@' . $domain;

    my $annotation_list = Cpanel::UserManager::Storage::list_annotations( ( full_username => $full_username ) );
    gather_email_accounts( \%service_accounts, { by_user => $full_username, constructor_args => [] } );
    gather_ftp_accounts( \%service_accounts, { by_user => $full_username, constructor_args => [] } );
    gather_webdisk_accounts( \%service_accounts, { by_user => $full_username, constructor_args => [] } );
    foreach my $service_accts_ar ( values %service_accounts ) {
        foreach my $this_account (@$service_accts_ar) {
            next if $this_account->full_username() ne $full_username;
            my $type       = $this_account->service();
            my $annotation = $annotation_list->lookup_by( $full_username, $type );
            push @accounts, $this_account if ( !defined $annotation || !$annotation->dismissed_merge );
        }
    }

    if ( !@accounts ) {    #there aren't any
        return undef;
    }
    elsif ( @accounts == 1 ) {    #just one, return it as a service account
        return $accounts[0]->$arg_obj_transform;
    }
    else {                        #more than one; make a hypothetical
        my $hypothetical_account = Cpanel::UserManager::Record::Lite->new(
            {
                type             => 'hypothetical',
                username         => $username,
                domain           => $domain,
                merge_candidates => [ map { $_->as_hashref } @accounts ],
            }
        );
        return $hypothetical_account->$arg_obj_transform;
    }
}

sub _list_pops {
    my ($by_user) = @_;
    my $arg = {};
    if ($by_user) {
        $arg = {
            'api.filter_column_0' => 'email',
            'api.filter_type_0'   => 'eq',
            'api.filter_term_0'   => $by_user,
        };
    }

    # Gathering disk usage information is too expensive of an operation
    $arg->{no_disk} = 1;

    # format_bytes is expensive
    $arg->{no_human_readable_keys} = 1;

    # Check to see if incoming is expensive
    $arg->{no_suspend_check} = 1;

    # TODO: Provide a way to filter by user@domain while reading these for the single service account lookup
    require Cpanel::API;
    my $resp = Cpanel::API::execute( 'Email', 'list_pops_with_disk', $arg );
    return _deduplicate( [qw(email domain)], $resp->data );
}

sub _list_ftp {
    my ($by_user) = @_;
    my $arg = {};
    if ($by_user) {
        $arg = {
            'api.filter_column_0' => 'login',
            'api.filter_type_0'   => 'eq',
            'api.filter_term_0'   => $by_user,
        };
    }

    # Since we do not need disk usage when using ProFTPD, we fallback to list_ftp().
    my $daemon_supports_quotas = Cpanel::FtpUtils::Server::determine_server_type() eq 'pure-ftpd' ? 1                    : 0;
    my $fn_name                = $daemon_supports_quotas                                          ? 'list_ftp_with_disk' : 'list_ftp';
    require Cpanel::API;
    my $resp = Cpanel::API::execute( 'Ftp', $fn_name, $arg );
    my $data = $resp->data;

    # Normalize:
    #  list_ftp and list_ftp_with_disk provide the absolute directory with different names,
    #  and only list_ftp_with_disk has reldir. We want reldir.
    if ( $data && 'list_ftp' eq $fn_name ) {
        require Cpanel::API::Ftp;
        for my $entry (@$data) {
            my $abs_ftp_homedir = $entry->{homedir} || $entry->{dir} || '/';
            $entry->{reldir} = Cpanel::API::Ftp::_getreldir_from_dir($abs_ftp_homedir);
        }
    }

    return _deduplicate( [qw(user)], $data );
}

sub _list_webdisk {

    require Cpanel::WebDisk;

    # TODO: Provide a way to filter by user@domain while reading these for the single service account lookup
    my @response = Cpanel::WebDisk::api2_listwebdisks();
    return _deduplicate( [qw(user domain)], \@response );
}

# Helper that, given an array ref of hash refs, will find any duplicate
# entries and eliminate them. It's possible for some files to get duplicate
# entries if two of the same API call are running simultaneously due to
# a race condition in the API and the ability to double-click the create
# button on the old interfaces. This bug predates our feature, but we
# need to account for it because the duplicates cause a problem in our UI.
sub _deduplicate {
    my ( $deduplicate_by, $data ) = @_;
    my @deduplicated_data;
    my %seen;
    no warnings 'uninitialized';
    for my $entry (@$data) {
        my $seen_key;
        for my $entry_key (@$deduplicate_by) {
            $seen_key .= $entry_key . chr(0) . $entry->{$entry_key} . chr(0);
        }
        if ( !$seen{$seen_key} ) {    # if we've never seen this entry before, include it
            push @deduplicated_data, $entry;
        }
        $seen{$seen_key}++;
    }
    return \@deduplicated_data;
}

sub _separate_service_accounts {
    my ($accounts) = @_;
    my ( @dismissed_service_accounts, @merged_service_accounts, @unlinked_service_accounts );
    for my $ac (@$accounts) {
        my $annotation = $ac->annotation;
        if ( $annotation && $annotation->dismissed_merge ) {
            push @dismissed_service_accounts, $ac;
        }
        elsif ( $annotation && $annotation->merged ) {
            push @merged_service_accounts, $ac;
        }
        else {
            push @unlinked_service_accounts, $ac;
        }
    }
    return ( \@dismissed_service_accounts, \@merged_service_accounts, \@unlinked_service_accounts );
}

sub gather_email_accounts {
    my ( $output, $opts ) = @_;
    $opts ||= {};

    my $args        = { @{ $opts->{constructor_args} } };
    my $email_users = _list_pops( $opts->{by_user} );
    for my $wmu (@$email_users) {
        my ( $username, $domain ) = split /\@/, $wmu->{email};
        my $annotation = $args->{annotation_list} ? $args->{annotation_list}->lookup_by( $wmu->{email}, 'email' ) : undef;
        my $record     = Cpanel::UserManager::Record::Lite->new(
            {
                type             => 'service',
                username         => $username,
                domain           => $domain,                                                                                    # may be undef, in which case this will be treated as a "special" account
                services         => { email => { enabled => 1, quota => int( ( $wmu->{_diskquota} || 0 ) / 1024 / 1024 ) } },
                can_set_quota    => 1,
                can_set_password => 1,
                ( $annotation ? ( dismissed => ( $annotation->dismissed_merge ? 1 : 0 ) ) : () ),
                @{ $opts->{constructor_args} || [] },
            }
        );

        # Skip services for the cPanel user since they are gathered separately
        if ( $record->full_username eq $record->{username} ) {
            next;
        }

        push @{ $output->{ $wmu->{email} } }, $record;
    }
    return;
}

sub gather_ftp_accounts {
    my ( $output, $opts ) = @_;
    $opts ||= {};

    my $args      = { @{ $opts->{constructor_args} } };
    my $ftp_users = _list_ftp( $opts->{by_user} );

    for my $fu (@$ftp_users) {
        my $annotation = $args->{annotation_list} ? $args->{annotation_list}->lookup_by( $fu->{user}, 'ftp' ) : undef;
        my ( $ftp_username, $ftp_domain ) = split /\@/, $fu->{user};

        if ( $fu->{type} eq 'main' || $fu->{type} eq 'logaccess' ) {

            # These account types don't have a domain for login.
            $ftp_domain = undef;
        }
        else {
            # For all other accounts, use the domain that was specified, or default it to the primary domain if no domain was specified.
            $ftp_domain ||= $Cpanel::CPDATA{'DNS'};
        }

        my $record = Cpanel::UserManager::Record::Lite->new(
            {
                type => 'service',

                # Unlinked FTP service accounts are always at the main domain,
                # because that was the only supported FTP domain prior to 11.54.
                username => $ftp_username,
                domain   => $ftp_domain,

                services         => { ftp => { enabled => 1, quota => $fu->{_diskquota}, homedir => $fu->{reldir} } },
                can_set_quota    => 1,
                can_set_password => 1,
                ( $annotation ? ( dismissed => ( $annotation->dismissed_merge ? 1 : 0 ) ) : () ),
                @{ $opts->{constructor_args} || [] },
            }
        );

        # Note: This will be 0.0 when unlimited, and 0.0 evaluates to true, so we need the extra greater-than check
        if ( $fu->{_diskquota} && $fu->{_diskquota} =~ /^[0-9.]+$/ && $fu->{_diskquota} > 0 ) {
            if ( $fu->{_diskused} >= $fu->{_diskquota} ) {
                $record->add_issue(
                    {
                        type    => 'error',
                        area    => 'quota',
                        service => 'ftp',
                        message => lh()->maketext( 'This account has exhausted its [asis,FTP] quota of “[_1]”.', $fu->{humandiskquota} ),
                        used    => $fu->{_diskused},
                        limit   => $fu->{_diskquota},
                    }
                );
            }
            elsif ( $fu->{_diskused} >= $fu->{_diskquota} * $percent_warn ) {
                $record->add_issue(
                    {
                        type    => 'warning',
                        area    => 'quota',
                        service => 'ftp',
                        message => lh()->maketext( 'This account has used “[_1]” of its [asis,FTP] quota of “[_2]”.', $fu->{humandiskused}, $fu->{humandiskquota} ),
                        used    => $fu->{_diskused},
                        limit   => $fu->{_diskquota},
                    }
                );
            }
        }

        # Skip services for the cPanel user since they are gathered separately
        if ( $record->full_username eq $record->username and $record->full_username !~ /_logs$/ ) {
            next;
        }

        if ( $fu->{type} eq 'main' or $fu->{type} eq 'logaccess' ) {
            $record->special(1);
            $record->can_set_quota(0);
            $record->can_set_password(0);
        }
        if ( $fu->{type} eq 'anonymous' ) {    # quota can still be changed
            $record->special(1);
            $record->can_set_password(0);
        }

        push @{ $output->{ $record->full_username } }, $record;
    }
    return;
}

sub gather_webdisk_accounts {
    my ( $output, $opts ) = @_;
    $opts ||= {};

    my $args          = { @{ $opts->{constructor_args} } };
    my $webdisk_users = _list_webdisk( $opts->{by_user} );
    for my $wdu (@$webdisk_users) {
        my $annotation = $args->{annotation_list} ? $args->{annotation_list}->lookup_by( $wdu->{login}, 'webdisk' ) : undef;
        my ( $username, $domain ) = split /\@/, $wdu->{login};
        my $record = Cpanel::UserManager::Record::Lite->new(
            {
                type             => 'service',
                username         => $username,
                domain           => $domain,
                services         => { webdisk => { enabled => 1, homedir => $wdu->{reldir}, enabledigest => $wdu->{hasdigest}, private => $wdu->{private}, perms => $wdu->{perms} } },
                can_set_quota    => 1,
                can_set_password => 1,
                ( $annotation ? ( dismissed => ( $annotation->dismissed_merge ? 1 : 0 ) ) : () ),
                @{ $opts->{constructor_args} || [] },
            }
        );

        # Skip services for the cPanel user since they are gathered separately
        if ( $record->full_username eq $record->username ) {
            next;
        }

        push @{ $output->{ $record->full_username } }, $record;
    }
    return;
}

sub gather_merge_candidates_for {
    my ($full_username) = @_;

    my ( %service_accounts, @merge_candidates, @dismissed_merge_candidates );

    gather_email_accounts( \%service_accounts, { by_user => $full_username, constructor_args => [] } );
    gather_ftp_accounts( \%service_accounts, { by_user => $full_username, constructor_args => [] } );
    gather_webdisk_accounts( \%service_accounts, { by_user => $full_username, constructor_args => [] } );

    my $annotation_list = Cpanel::UserManager::Storage::list_annotations( ( full_username => $full_username ) );

    my $service_accts_ar = $service_accounts{$full_username} || [];

    foreach my $this_account (@$service_accts_ar) {
        next if $this_account->full_username ne $full_username;    # should never happen, but just in case
        my $type       = $this_account->service();
        my $annotation = $annotation_list->lookup_by( $full_username, $type );
        next if $annotation && $annotation->merged;                # already merged, so we don't care about it as a potential mergable account
        if ( $annotation && $annotation->dismissed_merge ) {
            push @dismissed_merge_candidates, $this_account;
        }
        else {
            push @merge_candidates, $this_account;
        }
    }
    return ( \@merge_candidates, \@dismissed_merge_candidates );
}

sub lookup_service_password_hash {
    my ( $username, $domain, $service ) = @_;

    my $cpanel_user    = $Cpanel::user    || Cpanel::PwCache::getusername();
    my $cpanel_homedir = $Cpanel::homedir || Cpanel::PwCache::gethomedir();
    my $full_username  = $username . '@' . $domain;

    my $password_hash;
    if ( $service eq 'ftp' ) {
        $password_hash = Cpanel::AdminBin::Call::call( 'Cpanel', 'ftp_call', 'LOOKUP_PASSWORD_HASH', $username, $domain );
    }
    elsif ( $service eq 'email' ) {
        $password_hash = Cpanel::PwCache::PwFile::get_keyvalue_from_pwfile( "${cpanel_homedir}/etc/${domain}/shadow", 1, $username );
    }
    elsif ( $service eq 'webdisk' ) {
        $password_hash = Cpanel::PwCache::PwFile::get_keyvalue_from_pwfile( "${cpanel_homedir}/etc/webdav/shadow", 1, $full_username );
    }
    else {
        Carp::croak('Service type must be email, ftp, or webdisk.');
    }
    return $password_hash if length($password_hash);
    die lh()->maketext( 'The system failed to find the “[_1]” password hash for the “[_2]” user at the “[_3]” domain.', $service, $username, $domain );
}

sub _send_email_notification {
    my ( $user, $cookie ) = @_;

    my $full_username = $user->full_username;
    my $domain        = $user->domain;
    my $cpuser        = Cpanel::PwCache::getusername();

    Cpanel::AdminBin::Call::call(
        'Cpanel',
        'notify_call',
        'NOTIFY_NEW_USER',
        user              => $full_username,
        subaccount        => $full_username,
        cookie            => $cookie,
        user_domain       => $domain,
        origin            => $Cpanel::App::appname,
        source_ip_address => Cpanel::IP::Remote::get_current_remote_ip(),
    );

    return;
}

1;
